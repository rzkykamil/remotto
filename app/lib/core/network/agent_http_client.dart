import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'agent_status.dart';
import 'api_failure.dart';

/// HTTP client for the agent (api-spec): `GET /api/v1/status` and
/// `POST /api/v1/media/{action}`.
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
