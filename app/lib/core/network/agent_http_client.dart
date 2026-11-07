import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'agent_status.dart';
import 'api_failure.dart';

/// HTTP client for `GET /api/v1/status` on the agent (api-spec).
///
/// Transport errors map to [TimeoutFailure] or [UnreachableFailure]. Status
/// codes and bodies go through [parseStatusResponse]. The token is only sent
/// in the Authorization header and never appears in a failure or in a log.
final class AgentHttpClient {
  AgentHttpClient(this._client);

  final http.Client _client;

  /// Reads the agent status. Throws [ApiFailure] on any failure.
  Future<AgentStatus> getStatus({
    required String host,
    required int port,
    required String token,
    required Duration timeout,
  }) async {
    final uri = Uri.http('$host:$port', '/api/v1/status');
    try {
      final response = await _client
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(timeout);
      final body = utf8.decode(response.bodyBytes);
      return parseStatusResponse(
        response.statusCode,
        body,
        headers: response.headers,
      );
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
