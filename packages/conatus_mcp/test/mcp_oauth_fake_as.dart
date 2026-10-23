/// OAuth 发现测试用的本地假授权服务器（不访问外网）。
library;

import 'dart:convert';
import 'dart:io';

/// 一台本地假 AS：按路径返回受保护资源 / 授权服务器元数据，并记录 DCR 请求体。
class FakeAs {
  FakeAs._(this.server, this.issuer);

  /// 监听中的 HTTP server。
  final HttpServer server;

  /// 本 AS 的 issuer（`http://127.0.0.1:<port>`）。
  final Uri issuer;

  /// 动态注册收到的请求体。
  Map<String, Object?>? registeredBody;

  /// 以 `http://127.0.0.1:<port>` 形式的 origin。
  Uri get origin => Uri.parse('http://127.0.0.1:${server.port}');

  /// 启动假 AS；标志位控制哪些元数据路径可用。
  static Future<FakeAs> start({
    bool protectedResource = true,
    bool authorizationServer = true,
    bool openidFallback = false,
    bool unauthorizedProbe = false,
  }) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final FakeAs fake = FakeAs._(
      server,
      Uri.parse('http://127.0.0.1:${server.port}'),
    );
    server.listen((HttpRequest request) => fake._handle(
          request,
          protectedResource: protectedResource,
          authorizationServer: authorizationServer,
          openidFallback: openidFallback,
          unauthorizedProbe: unauthorizedProbe,
        ));
    return fake;
  }

  Future<void> _handle(
    HttpRequest request, {
    required bool protectedResource,
    required bool authorizationServer,
    required bool openidFallback,
    required bool unauthorizedProbe,
  }) async {
    final String path = request.uri.path;
    if (path == '/.well-known/oauth-protected-resource' ||
        path == '/alt-metadata') {
      if (path == '/alt-metadata' || protectedResource) {
        await _json(request, _resourceJson());
        return;
      }
    }
    if (path == '/mcp' && unauthorizedProbe) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.headers.set(
        HttpHeaders.wwwAuthenticateHeader,
        'Bearer resource_metadata="$issuer/alt-metadata"',
      );
      await request.response.close();
      return;
    }
    if (path == '/.well-known/oauth-authorization-server') {
      if (authorizationServer) {
        await _json(request, _metadataJson());
        return;
      }
    }
    if (path == '/.well-known/openid-configuration' && openidFallback) {
      await _json(request, _metadataJson());
      return;
    }
    if (path == '/register' && request.method == 'POST') {
      registeredBody = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, Object?>;
      await _json(request, <String, Object?>{'client_id': 'dcr-client-1'});
      return;
    }
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  Map<String, Object?> _resourceJson() => <String, Object?>{
        'resource': '$issuer/mcp',
        'authorization_servers': <String>['$issuer'],
      };

  Map<String, Object?> _metadataJson() => <String, Object?>{
        'issuer': '$issuer',
        'authorization_endpoint': '$issuer/authorize',
        'token_endpoint': '$issuer/token',
        'registration_endpoint': '$issuer/register',
        'scopes_supported': <String>['mcp', 'offline_access'],
      };

  Future<void> _json(HttpRequest request, Map<String, Object?> body) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  /// 关停监听。
  Future<void> close() => server.close(force: true);
}
