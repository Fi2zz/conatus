/// OAuth 授权服务器发现（RFC 9728 / 8414）测试；本地假 AS，不访问外网。
library;

import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'mcp_oauth_fake_as.dart';
import 'mcp_oauth_fake_clients.dart';

Future<FakeAs> _start([FakeAsScenario scenario = FakeAsScenario.happy]) async {
  final FakeAs fake = await FakeAs.start(scenario: scenario);
  addTearDown(fake.close);
  return fake;
}

http.Client _client() {
  final http.Client client = http.Client();
  addTearDown(client.close);
  return client;
}

void main() {
  group('discoverAuthServer', () {
    test('从 protected resource 找到授权服务器元数据', () async {
      final FakeAs fake = await _start();
      final McpAuthServerMetadata meta = await discoverAuthServer(
        Uri.parse('${fake.origin}/mcp'),
        client: _client(),
      );
      expect(meta.authorizationEndpoint.path, '/authorize');
      expect(meta.tokenEndpoint.path, '/token');
      expect(meta.registrationEndpoint?.path, '/register');
      expect(meta.scopesSupported, <String>['mcp', 'offline_access']);
    });

    test('oauth-authorization-server 404 时回退 openid-configuration', () async {
      final FakeAs fake = await _start(FakeAsScenario.openidOnly);
      final McpAuthServerMetadata meta = await discoverAuthServer(
        Uri.parse('${fake.origin}/mcp'),
        client: _client(),
      );
      expect(meta.tokenEndpoint.path, '/token');
    });

    test('well-known 失败时读 401 WWW-Authenticate 的 resource_metadata', () async {
      final FakeAs fake = await _start(FakeAsScenario.probeOnly);
      final McpAuthServerMetadata meta = await discoverAuthServer(
        Uri.parse('${fake.origin}/mcp'),
        client: _client(),
      );
      expect(meta.tokenEndpoint.path, '/token');
    });

    test('authorization_servers 为空时回退 401 探测', () async {
      final FakeAs fake = await _start(FakeAsScenario.emptyAuthServers);
      final McpAuthServerMetadata meta = await discoverAuthServer(
        Uri.parse('${fake.origin}/mcp'),
        client: _client(),
      );
      expect(meta.tokenEndpoint.path, '/token');
    });

    test('找不到授权服务器时抛 oauth-discovery', () async {
      final FakeAs fake = await _start(FakeAsScenario.broken);
      await expectLater(
        discoverAuthServer(Uri.parse('${fake.origin}/mcp'), client: _client()),
        throwsA(isA<McpException>()
            .having((McpException e) => e.code, 'code', 'oauth-discovery')),
      );
    });

    test('相对 / 非 http(s) URL 立即抛 oauth-discovery', () async {
      for (final Uri url in <Uri>[
        Uri.parse('/mcp'),
        Uri.parse('ftp://example.com/mcp'),
      ]) {
        await expectLater(
          discoverAuthServer(url, client: _client()),
          throwsA(isA<McpException>()
              .having((McpException e) => e.code, 'code', 'oauth-discovery')),
        );
      }
    });

    test('服务端不响应时按超时收敛为 oauth-discovery', () async {
      final Future<McpAuthServerMetadata> call = discoverAuthServer(
        Uri.parse('http://127.0.0.1:1/mcp'),
        client: HangingClient(),
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        call.timeout(const Duration(seconds: 2)),
        throwsA(isA<McpException>()
            .having((McpException e) => e.code, 'code', 'oauth-discovery')),
      );
    });

    test('传输失败收敛为 oauth-discovery', () async {
      await expectLater(
        discoverAuthServer(
          Uri.parse('http://127.0.0.1:1/mcp'),
          client: FailingClient(http.ClientException('boom')),
        ),
        throwsA(isA<McpException>()
            .having((McpException e) => e.code, 'code', 'oauth-discovery')),
      );
    });

    test('调用方注入的 client 不被关闭', () async {
      final FakeAs fake = await _start();
      final http.Client client = _client();
      await discoverAuthServer(
        Uri.parse('${fake.origin}/mcp'),
        client: client,
      );
      final http.Response response =
          await client.get(Uri.parse('${fake.origin}/alt-metadata'));
      expect(response.statusCode, 200);
    });
  });
}
