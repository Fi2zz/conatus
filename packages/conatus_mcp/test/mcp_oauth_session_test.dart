/// OAuth 授权码 + loopback 回调；本地假 AS，不访问外网。
library;

import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';

import 'mcp_oauth_fake_as.dart';
import 'mcp_oauth_session_support.dart';

void main() {
  test('authorize：PKCE + state + 回调换码，返回值完整', () async {
    final FakeAs fake = await startOAuthFake();
    final McpOAuthSession session = McpOAuthSession();
    addTearDown(session.close);
    Uri? opened;

    final McpOAuthToken token = await session.authorize(
      serverUrl: oauthServerUrl(fake),
      config: oauthConfig(),
      openUrl: (Uri url) {
        opened = url;
        answerCallback(url);
      },
    );

    expect(token.accessToken, 'access-1');
    expect(token.refreshToken, 'refresh-1');
    expect(token.scope, 'mcp');
    expect(token.expiresAt, isNotNull);
    expect(opened, isNotNull);
    expect(opened!.queryParameters['client_id'], 'cid');
    expect(opened!.queryParameters['scope'], 'mcp');
    expect(opened!.queryParameters['code_challenge_method'], 'S256');
    expect(opened!.queryParameters['code_challenge'], isNotEmpty);
    expect(
      opened!.queryParameters['redirect_uri'],
      startsWith('http://127.0.0.1:'),
    );

    final Map<String, String> request = fake.tokenRequests.single;
    expect(request['grant_type'], 'authorization_code');
    expect(request['code'], 'code-1');
    expect(request['client_id'], 'cid');
    expect(request['code_verifier'], isNotEmpty);
    expect(request['redirect_uri'], opened!.queryParameters['redirect_uri']);
  });

  test('callbackPort 固定时 redirect_uri 用该端口', () async {
    final FakeAs fake = await startOAuthFake();
    final McpOAuthSession session = McpOAuthSession();
    addTearDown(session.close);
    final int port = await freePort();
    Uri? opened;

    await session.authorize(
      serverUrl: oauthServerUrl(fake),
      config: McpOAuthConfig(
        clientId: 'cid',
        callbackPort: port,
        timeout: const Duration(seconds: 5),
      ),
      openUrl: (Uri url) {
        opened = url;
        answerCallback(url);
      },
    );

    expect(
      opened!.queryParameters['redirect_uri'],
      'http://127.0.0.1:$port/callback',
    );
  });

  test('state 不匹配：拒绝换码', () async {
    final FakeAs fake = await startOAuthFake();
    final McpOAuthSession session = McpOAuthSession();
    addTearDown(session.close);

    await expectLater(
      session.authorize(
        serverUrl: oauthServerUrl(fake),
        config: oauthConfig(),
        openUrl: (Uri url) => answerCallback(url, state: 'wrong-state'),
      ),
      oauthFailure('oauth-state'),
    );
    expect(fake.tokenRequests, isEmpty);
  });

  test('用户取消（error=access_denied）→ needs_auth', () async {
    final FakeAs fake = await startOAuthFake();
    final McpOAuthSession session = McpOAuthSession();
    addTearDown(session.close);

    await expectLater(
      session.authorize(
        serverUrl: oauthServerUrl(fake),
        config: oauthConfig(),
        openUrl: (Uri url) => answerCallback(url, error: 'access_denied'),
      ),
      oauthFailure('needs_auth'),
    );
  });

  test('等不到回调 → oauth-timeout', () async {
    final FakeAs fake = await startOAuthFake();
    final McpOAuthSession session = McpOAuthSession();
    addTearDown(session.close);

    await expectLater(
      session.authorize(
        serverUrl: oauthServerUrl(fake),
        config: oauthConfig(timeout: const Duration(milliseconds: 150)),
        openUrl: (Uri url) {},
      ),
      oauthFailure('oauth-timeout'),
    );
  });

  test('令牌端点非 200 → oauth-token，正文不进错误', () async {
    final FakeAs fake = await startOAuthFake();
    final McpOAuthSession session = McpOAuthSession();
    addTearDown(session.close);
    fake.tokenStatus = 500;
    fake.tokenResponse = <String, Object?>{'access_token': 'must-not-leak'};

    await expectLater(
      session.authorize(
        serverUrl: oauthServerUrl(fake),
        config: oauthConfig(),
        openUrl: answerCallback,
      ),
      throwsA(
        isA<McpException>()
            .having((McpException e) => e.code, 'code', 'oauth-token')
            .having(
              (McpException e) => e.message,
              'message',
              isNot(contains('must-not-leak')),
            ),
      ),
    );
  });
}
