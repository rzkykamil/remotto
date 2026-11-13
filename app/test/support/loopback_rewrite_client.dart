import 'package:http/http.dart' as http;

/// HTTP client that rewrites request hosts to loopback before sending.
///
/// Discovery only accepts private LAN addresses (D5/BR-12), so a candidate
/// such as `192.168.1.20` can never point at a loopback fake server directly.
/// Tests map those private hosts to `127.0.0.1` here instead. The port, path,
/// query and headers (including `Authorization`) are kept as they are, and
/// the candidate filter itself stays untouched.
final class LoopbackRewriteClient extends http.BaseClient {
  LoopbackRewriteClient(this._inner, this.hostMap);

  final http.Client _inner;

  /// Maps the host in a request URL to the host to dial, e.g.
  /// `{'192.168.1.20': '127.0.0.1'}`. Hosts not in the map are sent unchanged.
  final Map<String, String> hostMap;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final target = hostMap[request.url.host];
    if (target == null) return _inner.send(request);
    if (request is! http.Request) {
      throw UnsupportedError(
        'LoopbackRewriteClient only rewrites http.Request, '
        'got ${request.runtimeType}',
      );
    }
    final rewritten =
        http.Request(request.method, request.url.replace(host: target))
          ..headers.addAll(request.headers)
          ..bodyBytes = request.bodyBytes
          ..followRedirects = request.followRedirects
          ..maxRedirects = request.maxRedirects
          ..persistentConnection = request.persistentConnection;
    return _inner.send(rewritten);
  }

  @override
  void close() => _inner.close();
}
