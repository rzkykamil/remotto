import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Token yang dipakai server palsu. 64 karakter hex seperti token asli.
final String fakeAgentToken = 'a1' * 32;

/// Mode balasan server palsu. Mengikuti `docs/api-spec.md` untuk `GET /status`.
enum FakeAgentMode {
  /// 200 dengan `data` lengkap (token benar), 401 kalau token salah.
  ok,

  /// 403 `forbidden_network` untuk semua permintaan.
  forbidden,

  /// 429 `rate_limited` dengan header `Retry-After: 2`.
  rateLimited,

  /// 500 `internal`.
  serverError,

  /// 200 dengan body yang bukan JSON.
  badBody,

  /// Status tetap seperti [ok]; `POST /media/*` membalas 500 `media_failed`.
  mediaFailed,

  /// Status 200 dengan `volume` null; semua `/volume*` membalas 500
  /// `audio_failed`. Media tetap seperti [ok].
  audioFailed,
}

/// Satu permintaan ke rute `/api/v1/volume*`, termasuk yang ditolak.
final class FakeVolumeRequest {
  const FakeVolumeRequest(this.method, this.path, this.body);

  final String method;
  final String path;

  /// Body mentah. Kosong untuk permintaan tanpa body.
  final String body;
}

/// Server HTTP loopback yang meniru endpoint status agent.
///
/// Hanya bind ke `127.0.0.1` dengan port acak. [hold] membuat handler menunggu
/// sampai completer itu selesai (atau server ditutup), dipakai untuk menguji
/// timeout dan permintaan paralel.
final class FakeAgentServer {
  FakeAgentServer._(this._server, this._port);

  final HttpServer _server;
  final int _port;

  /// Token yang diterima server. Boleh diganti saat tes (mis. rotasi token).
  String token = fakeAgentToken;

  FakeAgentMode mode = FakeAgentMode.ok;

  /// Nama laptop di `data.name`.
  String name = 'Laptop-Kamil';

  /// False: `data.volume` null (Core Audio gagal di laptop).
  bool volumeAvailable = true;

  /// Level volume yang dilaporkan dan diubah oleh rute `/api/v1/volume*`.
  int volumeLevel = 35;

  /// Status mute yang dilaporkan dan diubah oleh rute `/api/v1/volume*`.
  bool volumeMuted = false;

  /// Jumlah request volume yang masih dibalas 500 `audio_failed`, lalu normal.
  int failNextVolumeRequests = 0;

  /// Jumlah permintaan yang sudah diterima handler.
  int requests = 0;

  /// Path setiap `POST /api/v1/media/*` yang diterima, sesuai urutan.
  final List<String> mediaPaths = [];

  /// Setiap permintaan `/api/v1/volume*` yang diterima, sesuai urutan. Termasuk
  /// permintaan yang ditolak (401, 400, 405, 500 karena mode atau hook).
  final List<FakeVolumeRequest> volumeRequests = [];

  /// Jumlah handler yang sedang berjalan sekarang.
  int inFlight = 0;

  /// Nilai tertinggi [inFlight] sepanjang hidup server.
  int maxInFlight = 0;

  /// Bila tidak null, handler menunggu completer ini sebelum membalas.
  Completer<void>? hold;

  final List<Completer<void>> _arrivals = [];
  final Completer<void> _stop = Completer<void>();
  bool _closed = false;

  int get port => _port;

  /// Mulai server di loopback. [port] 0 berarti port acak.
  static Future<FakeAgentServer> start({int port = 0}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final fake = FakeAgentServer._(server, server.port);
    fake._listen();
    return fake;
  }

  /// Menyalakan lagi server di port yang sama, untuk tes pemulihan koneksi.
  Future<FakeAgentServer> restart() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
    final fake = FakeAgentServer._(server, _port)
      ..token = token
      ..mode = mode
      ..name = name
      ..volumeAvailable = volumeAvailable
      ..volumeLevel = volumeLevel
      ..volumeMuted = volumeMuted
      ..failNextVolumeRequests = failNextVolumeRequests
      ..requests = requests;
    fake._listen();
    return fake;
  }

  /// Menunggu sampai handler sudah menerima [count] permintaan.
  Future<void> untilRequests(int count) {
    if (requests >= count) return Future<void>.value();
    final completer = Completer<void>();
    _arrivals.add(completer);
    return completer.future.timeout(const Duration(seconds: 5));
  }

  /// Menutup server dan membebaskan handler yang menunggu.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!_stop.isCompleted) _stop.complete();
    await _server.close(force: true);
  }

  void _listen() {
    _server.listen((request) {
      unawaited(_handle(request));
    });
  }

  Future<void> _handle(HttpRequest request) async {
    requests++;
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    for (final arrival in _arrivals.toList()) {
      if (!arrival.isCompleted) arrival.complete();
    }
    _arrivals.clear();

    try {
      // Body volume dibaca dan dicatat sebelum hold, supaya permintaan yang
      // menggantung tetap terlihat di [volumeRequests].
      var body = '';
      final path = request.uri.path;
      if (_isVolumePath(path)) {
        body = await utf8.decoder.bind(request).join();
        volumeRequests.add(FakeVolumeRequest(request.method, path, body));
      }

      final gate = hold;
      if (gate != null) {
        await Future.any<void>([gate.future, _stop.future]);
      }
      if (_closed) return;
      await _respond(request, body);
    } catch (_) {
      // Klien bisa sudah memutus koneksi; tes tidak perlu tahu.
    } finally {
      inFlight--;
    }
  }

  static const _statusPath = '/api/v1/status';
  static const _mediaPrefix = '/api/v1/media/';
  static const _mediaActions = {'play-pause', 'next', 'prev'};

  /// Rute volume dan method yang diizinkan. Path di luar peta ini 404.
  static const _volumeMethods = <String, Set<String>>{
    '/api/v1/volume': {'GET', 'PUT'},
    '/api/v1/volume/up': {'POST'},
    '/api/v1/volume/down': {'POST'},
    '/api/v1/volume/mute': {'POST'},
  };

  static bool _isVolumePath(String path) => _volumeMethods.containsKey(path);

  Future<void> _respond(HttpRequest request, String body) async {
    final response = request.response;
    final path = request.uri.path;
    final isMedia = path.startsWith(_mediaPrefix);
    final isVolume = _isVolumePath(path);

    if (!isMedia && !isVolume && path != _statusPath) {
      _writeError(response, 404, 'not_found', 'not found');
      return;
    }
    if (isMedia) {
      mediaPaths.add(path);
      if (request.method != 'POST') {
        _writeError(response, 405, 'method_not_allowed', 'method not allowed');
        return;
      }
      if (!_mediaActions.contains(path.substring(_mediaPrefix.length))) {
        _writeError(response, 404, 'not_found', 'not found');
        return;
      }
    }
    if (isVolume && !_volumeMethods[path]!.contains(request.method)) {
      _writeError(response, 405, 'method_not_allowed', 'method not allowed');
      return;
    }

    switch (mode) {
      case FakeAgentMode.forbidden:
        _writeError(response, 403, 'forbidden_network', 'forbidden');
      case FakeAgentMode.rateLimited:
        response.headers.set('Retry-After', '2');
        _writeError(response, 429, 'rate_limited', 'too many requests');
      case FakeAgentMode.serverError:
        _writeError(response, 500, 'internal', 'internal error');
      case FakeAgentMode.badBody:
        _writeRaw(response, 200, '<html>bukan json</html>');
      case FakeAgentMode.ok:
      case FakeAgentMode.mediaFailed:
      case FakeAgentMode.audioFailed:
        if (request.headers.value('authorization') != 'Bearer $token') {
          _writeError(response, 401, 'invalid_token', 'invalid token');
          return;
        }
        if (isVolume) {
          _respondVolume(response, request.method, path, body);
          return;
        }
        if (!isMedia) {
          _writeRaw(response, 200, jsonEncode({'data': _statusData()}));
          return;
        }
        if (mode == FakeAgentMode.mediaFailed) {
          _writeError(response, 500, 'media_failed', 'media key failed');
          return;
        }
        final action = path.substring(_mediaPrefix.length);
        _writeRaw(
          response,
          200,
          jsonEncode({
            'data': {'action': action},
          }),
        );
    }
  }

  /// Rute `/api/v1/volume*` setelah auth. Urutan: audio gagal (mode atau hook),
  /// lalu validasi body, lalu perubahan state.
  void _respondVolume(
    HttpResponse response,
    String method,
    String path,
    String body,
  ) {
    if (mode == FakeAgentMode.audioFailed || _consumeFailNextVolume()) {
      _writeError(response, 500, 'audio_failed', 'audio failed');
      return;
    }

    switch (path) {
      case '/api/v1/volume':
        if (method == 'GET') {
          _writeVolume(response);
          return;
        }
        final data = _decodeObject(body);
        final level = data?['level'];
        if (level is! int) {
          _writeError(
            response,
            400,
            'invalid_request',
            'level must be integer',
          );
          return;
        }
        if (level < 0 || level > 100) {
          _writeError(response, 400, 'invalid_level', 'level out of range');
          return;
        }
        volumeLevel = level;
        volumeMuted = false;
        _writeVolume(response);
      case '/api/v1/volume/up':
        volumeLevel = (volumeLevel + 5).clamp(0, 100).toInt();
        volumeMuted = false;
        _writeVolume(response);
      case '/api/v1/volume/down':
        volumeLevel = (volumeLevel - 5).clamp(0, 100).toInt();
        volumeMuted = false;
        _writeVolume(response);
      case '/api/v1/volume/mute':
        final muted = _decodeObject(body)?['muted'];
        if (muted is! bool) {
          _writeError(response, 400, 'invalid_request', 'muted must be bool');
          return;
        }
        volumeMuted = muted;
        _writeVolume(response);
    }
  }

  bool _consumeFailNextVolume() {
    if (failNextVolumeRequests <= 0) return false;
    failNextVolumeRequests--;
    return true;
  }

  Map<String, Object?>? _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  void _writeVolume(HttpResponse response) {
    _writeRaw(
      response,
      200,
      jsonEncode({
        'data': {'level': volumeLevel, 'muted': volumeMuted},
      }),
    );
  }

  Map<String, Object?> _statusData() => {
    'name': name,
    'version': '1.0.0',
    'uptimeSeconds': 120,
    'volume': volumeAvailable && mode != FakeAgentMode.audioFailed
        ? {'level': volumeLevel, 'muted': volumeMuted}
        : null,
    'pending': null,
  };

  void _writeError(
    HttpResponse response,
    int status,
    String code,
    String message,
  ) {
    _writeRaw(
      response,
      status,
      jsonEncode({
        'error': {'code': code, 'message': message},
      }),
    );
  }

  void _writeRaw(HttpResponse response, int status, String body) {
    response.statusCode = status;
    response.headers.set('Content-Type', 'application/json; charset=utf-8');
    response.headers.set('Cache-Control', 'no-store');
    response.write(body);
    unawaited(response.close());
  }
}
