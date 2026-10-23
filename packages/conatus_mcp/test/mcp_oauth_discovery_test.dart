/// OAuth 授权服务器发现（RFC 9728 / 8414）与动态客户端注册（RFC 7591）测试。
///
/// 全部走本地 [FakeAs]，不访问外网。
library;

import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'mcp_oauth_fake_as.dart';

final Uri _authorize = Uri.parse('https://as.example/authorize');
final Uri _token = Uri.parse('https://as.example/token');

void main() {
  late FakeAs fake;
  late http.Client client;

  setUp(() => client = http.Client());
  tearDown(() async {
    client.close();
    await fake.close();
  });

  group('discoverAuthServer', () {
    test('从 protected resource 找到授权服务器元数据', () async {
      fake = await FakeAs.start();
      final McpAuthServerMetadata meta = await discoverAuthServer(
        Uri.parse('${fake.origin}/mcp'),
        client: client,
      );
      expect(meta.authorizationEndpoint.path, '/authorize');
      expect(meta.tokenEndpoint.path, '/token');
      expect(meta.registrationEndpoint?.path, '/register');
      expect(meta.scopesSupported, <String>['mcp', 'offline_access']);
    });

    test('oauth-authorization-server 404 时回退 openid-configuration', () async {
      fake = await FakeAs.start(
        authorizationServer: false,
        openidFallback: true,
      );
      final McpAuthServerMetadata meta = await discoverAuthServer(
        Uri.parse('${fake.origin}/mcp'),
        client: client,
      );
      expect(meta.tokenEndpoint.path, '/token');
    });

    test('well-known 失败时读 401 WWW-Authenticate 的 resource_metadata', () async {
      fake = await FakeAs.start(
        protectedResource: false,
        unauthorizedProbe: true,
      );
      final McpAuthServerMetadata meta = await discoverAuthServer(
        Uri.parse('${fake.origin}/mcp'),
        client: client,
      );
      expect(meta.tokenEndpoint.path, '/token');
    });

    test('找不到授权服务器时抛 oauth-discovery', () async {
      fake = await FakeAs.start(
        protectedResource: false,
        authorizationServer: false,
      );
      await expectLater(
        discoverAuthServer(Uri.parse('${fake.origin}/mcp'), client: client),
        throwsA(isA<McpException>()
            .having((McpException e) => e.code, 'code', 'oauth-discovery')),
      );
    });
  });

  group('registerOAuthClient', () {
    test('POST 注册端点并返回 client_id', () async {
      fake = await FakeAs.start();
      final McpAuthServerMetadata meta = await discoverAuthServer(
        Uri.parse('${fake.origin}/mcp'),
        client: client,
      );
      final String clientId = await registerOAuthClient(
        meta,
        Uri.parse('http://127.0.0.1:7777/callback'),
        client: client,
      );

      expect(clientId, 'dcr-client-1');
      final Map<String, Object?> body = fake.registeredBody!;
      expect(body['redirect_uris'], <String>['http://127.0.0.1:7777/callback']);
      expect(
          body['grant_types'], <String>['authorization_code', 'refresh_token']);
      expect(body['response_types'], <String>['code']);
      expect(body['token_endpoint_auth_method'], 'none');
      expect(body['client_name'], isNotEmpty);
    });

    test('无注册端点且未配置 client_id 时抛 oauth-no-client', () async {
      fake = await FakeAs.start();
      final McpAuthServerMetadata meta = McpAuthServerMetadata(
        authorizationEndpoint: _authorize,
        tokenEndpoint: _token,
      );
      await expectLater(
        registerOAuthClient(
          meta,
          Uri.parse('http://127.0.0.1:7777/callback'),
          client: client,
        ),
        throwsA(isA<McpException>()
            .having((McpException e) => e.code, 'code', 'oauth-no-client')),
      );
    });

    test('无注册端点时使用配置的 client_id', () async {
      fake = await FakeAs.start();
      final McpAuthServerMetadata meta = McpAuthServerMetadata(
        authorizationEndpoint: _authorize,
        tokenEndpoint: _token,
      );
      final String clientId = await registerOAuthClient(
        meta,
        Uri.parse('http://127.0.0.1:7777/callback'),
        client: client,
        config: const McpOAuthConfig(clientId: 'configured-id'),
      );
      expect(clientId, 'configured-id');
    });
  });
}
