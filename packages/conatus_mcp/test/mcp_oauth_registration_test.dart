/// 动态客户端注册（RFC 7591）测试；本地假 AS，不访问外网。
library;

import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'mcp_oauth_fake_as.dart';
import 'mcp_oauth_fake_clients.dart';

final Uri _callback = Uri.parse('http://127.0.0.1:7777/callback');

Future<FakeAs> _start() async {
  final FakeAs fake = await FakeAs.start();
  addTearDown(fake.close);
  return fake;
}

http.Client _client() {
  final http.Client client = http.Client();
  addTearDown(client.close);
  return client;
}

McpAuthServerMetadata _metaFor(FakeAs fake, {bool registration = true}) =>
    McpAuthServerMetadata(
      authorizationEndpoint: Uri.parse('${fake.issuer}/authorize'),
      tokenEndpoint: Uri.parse('${fake.issuer}/token'),
      registrationEndpoint:
          registration ? Uri.parse('${fake.origin}/register') : null,
    );

void main() {
  group('registerOAuthClient', () {
    test('POST 注册端点并返回 client_id', () async {
      final FakeAs fake = await _start();
      final String clientId = await registerOAuthClient(
        _metaFor(fake),
        _callback,
        client: _client(),
      );

      expect(clientId, 'dcr-client-1');
      final Map<String, Object?> body = fake.registeredBody!;
      expect(body['redirect_uris'], <String>[_callback.toString()]);
      expect(
          body['grant_types'], <String>['authorization_code', 'refresh_token']);
      expect(body['response_types'], <String>['code']);
      expect(body['token_endpoint_auth_method'], 'none');
      expect(body['client_name'], isNotEmpty);
      expect(body.containsKey('client_secret'), isFalse);
      expect(body.containsKey('scope'), isFalse);
    });

    test('配置的 scope 随注册请求下发', () async {
      final FakeAs fake = await _start();
      await registerOAuthClient(
        _metaFor(fake),
        _callback,
        client: _client(),
        config: const McpOAuthConfig(scope: 'mcp offline_access'),
      );
      expect(fake.registeredBody!['scope'], 'mcp offline_access');
    });

    test('已有配置 client_id 时跳过 DCR', () async {
      final FakeAs fake = await _start();
      final String clientId = await registerOAuthClient(
        _metaFor(fake),
        _callback,
        client: _client(),
        config: const McpOAuthConfig(clientId: 'configured-id'),
      );
      expect(clientId, 'configured-id');
      expect(fake.registeredBody, isNull);
    });

    test('client_secret 不下发到 DCR 请求体', () async {
      final FakeAs fake = await _start();
      await registerOAuthClient(
        _metaFor(fake),
        _callback,
        client: _client(),
        config: const McpOAuthConfig(clientSecret: 'shh'),
      );
      expect(fake.registeredBody, isNotNull);
      expect(fake.registeredBody!.containsKey('client_secret'), isFalse);
    });

    test('无注册端点且未配置 client_id 时抛 oauth-no-client', () async {
      final FakeAs fake = await _start();
      await expectLater(
        registerOAuthClient(
          _metaFor(fake, registration: false),
          _callback,
          client: _client(),
        ),
        throwsA(isA<McpException>()
            .having((McpException e) => e.code, 'code', 'oauth-no-client')),
      );
    });

    test('无注册端点时使用配置的 client_id', () async {
      final FakeAs fake = await _start();
      final String clientId = await registerOAuthClient(
        _metaFor(fake, registration: false),
        _callback,
        client: _client(),
        config: const McpOAuthConfig(clientId: 'configured-id'),
      );
      expect(clientId, 'configured-id');
    });

    test('注册端点非 2xx → oauth-registration', () async {
      final FakeAs fake = await _start();
      fake.registrationStatus = 400;
      await expectLater(
        registerOAuthClient(_metaFor(fake), _callback, client: _client()),
        throwsA(isA<McpException>()
            .having((McpException e) => e.code, 'code', 'oauth-registration')),
      );
    });

    test('注册响应缺 client_id → oauth-registration', () async {
      final FakeAs fake = await _start();
      fake.registrationResponse = const <String, Object?>{};
      await expectLater(
        registerOAuthClient(_metaFor(fake), _callback, client: _client()),
        throwsA(isA<McpException>()
            .having((McpException e) => e.code, 'code', 'oauth-registration')),
      );
    });

    test('注册请求超时 → oauth-registration', () async {
      final FakeAs fake = await _start();
      final Future<String> call = registerOAuthClient(
        _metaFor(fake),
        _callback,
        client: HangingClient(),
        config: const McpOAuthConfig(timeout: Duration(milliseconds: 20)),
      );
      await expectLater(
        call.timeout(const Duration(seconds: 2)),
        throwsA(isA<McpException>()
            .having((McpException e) => e.code, 'code', 'oauth-registration')),
      );
    });

    test('注册传输失败 → oauth-registration', () async {
      final FakeAs fake = await _start();
      await expectLater(
        registerOAuthClient(
          _metaFor(fake),
          _callback,
          client: FailingClient(http.ClientException('boom')),
        ),
        throwsA(isA<McpException>()
            .having((McpException e) => e.code, 'code', 'oauth-registration')),
      );
    });
  });
}
