import 'dart:convert';

/// Failure when talking to the agent. Mapped from the HTTP status code and
/// the error code in `docs/api-spec.md`. UI text comes from app strings, not
/// from the server `message`. The token never enters this type.
sealed class ApiFailure implements Exception {
  const ApiFailure({this.code});

  /// `code` from the error envelope, e.g. `invalid_token`. Null if absent.
  final String? code;

  @override
  String toString() => '$runtimeType(code: $code)';
}

/// 401: token missing or wrong (BR-1). The app enters the re-pairing flow.
final class UnauthorizedFailure extends ApiFailure {
  const UnauthorizedFailure({super.code});
}

/// 403: source address outside the allowed LAN.
final class ForbiddenFailure extends ApiFailure {
  const ForbiddenFailure({super.code});
}

/// 429: rate limit. [retryAfter] from the `Retry-After` header if present.
final class RateLimitedFailure extends ApiFailure {
  const RateLimitedFailure({super.code, this.retryAfter});

  final Duration? retryAfter;
}

/// 500 or another unmapped status code. Also used when a 2xx body
/// does not match the contract. [code] is null if the body has no error code.
final class ServerFailure extends ApiFailure {
  const ServerFailure({super.code});
}

/// Agent unreachable: connection refused or no route.
final class UnreachableFailure extends ApiFailure {
  const UnreachableFailure();
}

/// Request exceeded the time limit (3 seconds for polling and commands, technical-spec §6).
final class TimeoutFailure extends ApiFailure {
  const TimeoutFailure();
}

/// Unwraps the agent response envelope. A 2xx status yields the `data` content.
/// Other statuses are mapped to [ApiFailure]. Header names are matched
/// case-insensitively.
Map<String, Object?> unwrapAgentResponse(
  int statusCode,
  String body, {
  Map<String, String> headers = const {},
}) {
  if (statusCode >= 200 && statusCode < 300) {
    final decoded = _tryDecode(body);
    if (decoded is Map<String, Object?>) {
      final data = decoded['data'];
      if (data is Map<String, Object?>) return data;
    }
    throw const ServerFailure();
  }

  final code = _errorCode(_tryDecode(body));
  throw switch (statusCode) {
    401 => UnauthorizedFailure(code: code),
    403 => ForbiddenFailure(code: code),
    429 => RateLimitedFailure(code: code, retryAfter: _retryAfter(headers)),
    _ => ServerFailure(code: code),
  };
}

Object? _tryDecode(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
}

String? _errorCode(Object? decoded) {
  if (decoded is! Map<String, Object?>) return null;
  final error = decoded['error'];
  if (error is! Map<String, Object?>) return null;
  final code = error['code'];
  return code is String ? code : null;
}

Duration? _retryAfter(Map<String, String> headers) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() != 'retry-after') continue;
    final seconds = int.tryParse(entry.value.trim());
    return seconds == null ? null : Duration(seconds: seconds);
  }
  return null;
}
