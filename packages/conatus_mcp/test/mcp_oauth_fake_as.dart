/// OAuth 测试用的本地假授权服务器（不访问外网）。
library;

import 'dart:convert';
import 'dart:io';

const String _prPath = '/.well-known/oauth-protected-resource';
const String _asPath = '/.well-known/oauth-authorization-server';
const String _oidcPath = '/.well-known/openid-configuration';
const String _altPath = '/alt-metadata';

/// 假 AS 的发现面场景。
enum FakeAsScenario {
  /// 受保护资源 + 授权服务器元数据全可用。
  happy,

  /// 只有 OIDC 文档（`oauth-authorization-server` 404）。
  openidOnly,

  /// 受保护资源文档缺失，靠 401 `resource_metadata` 发现。
  probeOnly,

  /// 受保护资源文档存在但 `authorization_servers` 为空。
  emptyAuthServers,

  /// 所有发现路径都 404。
  broken,
}

/// 一台本地假 AS：按场景返回元数据，并记录 DCR 请求体。
class FakeAs {
  FakeAs._(this.server, this.issuer, this.scenario);

  /// 监听中的 HTTP server。
  final HttpServer server;

  /// 本 AS 的 issuer（`http://127.0.0.1:<port>`）。
  final Uri issuer;

  /// 当前场景。
  final FakeAsScenario scenario;

  /// DCR 收到的请求体（未注册时为 `null`）。
  Map<String, Object?>? registeredBody;

  /// DCR 返回的 HTTP 状态码。
  int registrationStatus = HttpStatus.ok;

  /// DCR 返回的 JSON 体。
  Map<String, Object?> registrationResponse = <String, Object?>{
    'client_id': 'dcr-client-1',
  };

  /// 以 `http://127.0.0.1:<port>` 形式的 origin。
  Uri get origin => issuer;

  /// 启动假 AS。
  static Future<FakeAs> start({
    FakeAsScenario scenario = FakeAsScenario.happy,
  }) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final FakeAs fake = FakeAs._(
      server,
      Uri.parse('http://127.0.0.1:${server.port}'),
      scenario,
    );
    server.listen(fake._handle);
    return fake;
  }

  Future<void> _handle(HttpRequest request) async {
    final Map<String, Object?>? document = _documents[request.uri.path];
    if (document != null) {
      await _json(request, document);
      return;
    }
    if (request.uri.path == '/mcp' && _probes) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.headers.set(
        HttpHeaders.wwwAuthenticateHeader,
        'Bearer resource_metadata="$issuer$_altPath"',
      );
      await request.response.close();
      return;
    }
    if (request.uri.path == '/register' && request.method == 'POST') {
      registeredBody = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, Object?>;
      request.response.statusCode = registrationStatus;
      await _json(request, registrationResponse);
      return;
    }
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  bool get _probes =>
      scenario == FakeAsScenario.probeOnly ||
      scenario == FakeAsScenario.emptyAuthServers;

  Map<String, Map<String, Object?>> get _documents {
    final Map<String, Object?> resource = _resourceJson(<String>['$issuer']);
    final Map<String, Object?> metadata = _metadataJson();
    return switch (scenario) {
      FakeAsScenario.happy => <String, Map<String, Object?>>{
          _prPath: resource,
          _asPath: metadata,
          _altPath: resource,
        },
      FakeAsScenario.emptyAuthServers => <String, Map<String, Object?>>{
          _prPath: _resourceJson(const <String>[]),
          _asPath: metadata,
          _altPath: resource,
        },
      FakeAsScenario.openidOnly => <String, Map<String, Object?>>{
          _prPath: resource,
          _oidcPath: metadata,
        },
      FakeAsScenario.probeOnly => <String, Map<String, Object?>>{
          _altPath: resource,
          _asPath: metadata,
        },
      FakeAsScenario.broken => const <String, Map<String, Object?>>{},
    };
  }

  Map<String, Object?> _resourceJson(List<String> servers) => <String, Object?>{
        'resource': '$issuer/mcp',
        'authorization_servers': servers,
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
