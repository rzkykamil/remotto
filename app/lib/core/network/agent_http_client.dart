import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'agent_status.dart';
import 'api_failure.dart';

/// HTTP client for the agent (api-spec): `GET /api/v1/status`,
/// `POST /api/v1/media/{action}`, and the `/api/v1/volume` endpoints.
///
/// Transport errors map to [TimeoutFailure] or [UnreachableFailure]. Status
/// codes and bodies go through [parseStatusResponse] or [unwrapAgentResponse].
/// The token is only sent in the Authorization header and never appears in a
/// failure or in a log.
final class AgentHttpClient {
  AgentHttpClient(this._client);

  final http.Client _client;

  /// Reads the agent status. Throws [ApiFailure] on any failure.
  Future<AgentStatus> getStatus({
    required String host,
    required int port,
    required String token,
    required Duration timeout,
  }) {
    final uri = Uri.http('$host:$port', '/api/v1/status');
    return _guard(() async {
      final response = await _client.get(uri, headers: _headers(token));
      final body = utf8.decode(response.bodyBytes);
      return parseStatusResponse(
        response.statusCode,
        body,
        headers: response.headers,
      );
    }, timeout);
  }

  /// Sends one media command (`play-pause`, `next`, `prev`). Not idempotent,
  /// so this method never retries. Throws [ApiFailure] on any failure.
  Future<void> postMedia({
    required String host,
    required int port,
    required String token,
    required String action,
    required Duration timeout,
  }) {
    final uri = Uri.http('$host:$port', '/api/v1/media/$action');
    return _guard(() async {
      final response = await _client.post(uri, headers: _headers(token));
      final body = utf8.decode(response.bodyBytes);
      final data = unwrapAgentResponse(
        response.statusCode,
        body,
        headers: response.headers,
      );
      if (data['action'] != action) throw const ServerFailure();
    }, timeout);
  }

  /// `PUT /api/v1/volume` with `{"level": n}`. Returns the latest volume.
  /// Never retries here: the retry lives in the state layer (VolumeSender).
  Future<VolumeStatus> putVolume({
    required String host,
    required int port,
    required String token,
    required int level,
    required Duration timeout,
  }) {
    return _sendVolume(
      host: host,
      port: port,
      token: token,
      method: 'PUT',
      path: '/api/v1/volume',
      body: {'level': level},
      timeout: timeout,
    );
  }

  /// `POST /api/v1/volume/up` or `/down` with no body. [direction] is `up` or
  /// `down`. Never retries.
  Future<VolumeStatus> postVolumeStep({
    required String host,
    required int port,
    required String token,
    required String direction,
    required Duration timeout,
  }) {
    return _sendVolume(
      host: host,
      port: port,
      token: token,
      method: 'POST',
      path: '/api/v1/volume/$direction',
      timeout: timeout,
    );
  }

  /// `POST /api/v1/volume/mute` with `{"muted": b}`. Never retries here.
  Future<VolumeStatus> postVolumeMute({
    required String host,
    required int port,
    required String token,
    required bool muted,
    required Duration timeout,
  }) {
    return _sendVolume(
      host: host,
      port: port,
      token: token,
      method: 'POST',
      path: '/api/v1/volume/mute',
      body: {'muted': muted},
      timeout: timeout,
    );
  }

  /// Shared path for every `/volume` call. Every success body is the latest
  /// `Volume` object (api-spec, Volume section).
  Future<VolumeStatus> _sendVolume({
    required String host,
    required int port,
    required String token,
    required String method,
    required String path,
    required Duration timeout,
    Map<String, Object?>? body,
  }) {
    final uri = Uri.http('$host:$port', path);
    return _guard(() async {
      final headers = {
        ..._headers(token),
        if (body != null) 'Content-Type': 'application/json',
      };
      final encoded = body == null ? null : jsonEncode(body);
      final response = method == 'PUT'
          ? await _client.put(uri, headers: headers, body: encoded)
          : await _client.post(uri, headers: headers, body: encoded);
      final text = utf8.decode(response.bodyBytes);
      final data = unwrapAgentResponse(
        response.statusCode,
        text,
        headers: response.headers,
      );
      return VolumeStatus.fromData(data);
    }, timeout);
  }

  Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
  };

  /// Runs [send] with [timeout] and maps every failure to an [ApiFailure].
  /// [ApiFailure]s pass through unchanged.
  Future<T> _guard<T>(Future<T> Function() send, Duration timeout) async {
    try {
      return await send().timeout(timeout);
    } on ApiFailure {
      rethrow;
    } on TimeoutException {
      throw const TimeoutFailure();
    } on FormatException {
      // The body is not valid UTF-8, so it does not match the contract.
      throw const ServerFailure();
    } on SocketException {
      throw const UnreachableFailure();
    } on HandshakeException {
      throw const UnreachableFailure();
    } on http.ClientException {
      throw const UnreachableFailure();
    } on OSError {
      throw const UnreachableFailure();
    } catch (_) {
      // The error is not forwarded: it may contain the URI or headers.
      throw const UnreachableFailure();
    }
  }
}
