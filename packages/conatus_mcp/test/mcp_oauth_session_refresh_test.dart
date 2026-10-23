/// OAuth 刷新：refresh_token 换新令牌、跨进程元数据与失败收敛。
library;

import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';

import 'mcp_oauth_fake_as.dart';
import 'mcp_oauth_session_support.dart';

void main() {
  test('refresh：用 refresh_token 换新令牌', () async {
    final FakeAs fake = await startOAuthFake();
    final McpOAuthSession session = McpOAuthSession();
    addTearDown(session.close);
    final McpOAuthToken token = await session.authorize(
      serverUrl: oauthServerUrl(fake),
      config: oauthConfig(),
      openUrl: answerCallback,
    );

    fake.tokenResponse = <String, Object?>{
      'access_token': 'access-2',
      'refresh_token': 'refresh-2',
      'expires_in': 7200,
    };
    final McpOAuthToken refreshed = await session.refresh(token);

    expect(refreshed.accessToken, 'access-2');
    expect(refreshed.refreshToken, 'refresh-2');
    expect(fake.tokenRequests.last['grant_type'], 'refresh_token');
    expect(fake.tokenRequests.last['refresh_token'], 'refresh-1');
  });

  test('新进程 refresh：显式传 meta 即可工作', () async {
    final FakeAs fake = await startOAuthFake();
    final McpOAuthSession first = McpOAuthSession();
    addTearDown(first.close);
    final McpOAuthToken token = await first.authorize(
      serverUrl: oauthServerUrl(fake),
      config: oauthConfig(),
      openUrl: answerCallback,
    );
    final McpAuthServerMetadata meta = await discoverAuthServer(
      oauthServerUrl(fake),
    );
    final McpOAuthSession second = McpOAuthSession();
    addTearDown(second.close);

    await second.refresh(token, meta: meta, config: oauthConfig());

    expect(fake.tokenRequests.last['refresh_token'], 'refresh-1');
    expect(fake.tokenRequests.last['client_id'], 'cid');
  });

  test('refresh 失败 → needs_auth，且消息不含令牌', () async {
    final FakeAs fake = await startOAuthFake();
    final McpOAuthSession session = McpOAuthSession();
    addTearDown(session.close);
    final McpOAuthToken token = await session.authorize(
      serverUrl: oauthServerUrl(fake),
      config: oauthConfig(),
      openUrl: answerCallback,
    );

    fake.tokenStatus = 400;
    fake.tokenResponse = <String, Object?>{
      'error': 'invalid_grant',
      'access_token': 'must-not-leak',
    };

    await expectLater(
      session.refresh(token),
      throwsA(
        isA<McpException>()
            .having((McpException e) => e.code, 'code', 'needs_auth')
            .having(
              (McpException e) => e.message,
              'message',
              isNot(contains('must-not-leak')),
            ),
      ),
    );
  });

  test('没有 refresh_token → needs_auth，不发请求', () async {
    final FakeAs fake = await startOAuthFake();
    final McpOAuthSession session = McpOAuthSession();
    addTearDown(session.close);
    final McpAuthServerMetadata meta = await discoverAuthServer(
      oauthServerUrl(fake),
    );
    final int requestsBefore = fake.tokenRequests.length;

    await expectLater(
      session.refresh(
        const McpOAuthToken(accessToken: 'a'),
        meta: meta,
        config: oauthConfig(),
      ),
      oauthFailure('needs_auth'),
    );
    expect(fake.tokenRequests, hasLength(requestsBefore));
  });
}
