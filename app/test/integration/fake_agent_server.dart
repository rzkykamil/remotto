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

  /// Jumlah permintaan yang sudah diterima handler.
  int requests = 0;

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
      final gate = hold;
      if (gate != null) {
        await Future.any<void>([gate.future, _stop.future]);
      }
      if (_closed) return;
      await _respond(request);
    } catch (_) {
      // Klien bisa sudah memutus koneksi; tes tidak perlu tahu.
    } finally {
      inFlight--;
    }
  }

  Future<void> _respond(HttpRequest request) async {
    final response = request.response;

    if (request.uri.path != '/api/v1/status') {
      _writeError(response, 404, 'not_found', 'not found');
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
        if (request.headers.value('authorization') != 'Bearer $token') {
          _writeError(response, 401, 'invalid_token', 'invalid token');
          return;
        }
        _writeRaw(response, 200, jsonEncode({'data': _statusData()}));
    }
  }

  Map<String, Object?> _statusData() => {
    'name': name,
    'version': '1.0.0',
    'uptimeSeconds': 120,
    'volume': volumeAvailable ? {'level': 35, 'muted': false} : null,
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
