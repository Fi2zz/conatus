/// OAuth 刷新：refresh_token 换新令牌、跨进程元数据与失败收敛。
library;

import 'dart:io';

import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';

import 'mcp_oauth_fake_as.dart';
import 'mcp_oauth_session_support.dart';

void main() {
  test('refresh：用 refresh_token 换新令牌', () async {
    final FakeAs fake = await startOAuthFake();
    final McpOAuthSession session = oauthSession();
    final McpOAuthToken token = await session.authorize(
      serverUrl: oauthServerUrl(fake),
      config: oauthConfig(),
      openUrl: answerCallback,
    );

    fake.tokenResponse = <String, Object?>{
      'access_token': 'access-2',
      'refresh_token': 'refresh-2',
      'expires_in': '7200',
    };
    final McpOAuthToken refreshed = await session.refresh(token);

    expect(refreshed.accessToken, 'access-2');
    expect(refreshed.refreshToken, 'refresh-2');
    expect(refreshed.expiresAt, isNotNull);
    expect(fake.tokenRequests.last['grant_type'], 'refresh_token');
    expect(fake.tokenRequests.last['refresh_token'], 'refresh-1');
  });

  test('AS 不轮换 refresh_token 时保留旧令牌', () async {
    final FakeAs fake = await startOAuthFake();
    final McpOAuthSession session = oauthSession();
    final McpOAuthToken token = await session.authorize(
      serverUrl: oauthServerUrl(fake),
      config: oauthConfig(),
      openUrl: answerCallback,
    );

    // 只下发 access_token：非轮换授权服务器的典型响应。
    fake.tokenResponse = <String, Object?>{
      'access_token': 'access-2',
      'expires_in': 3600,
    };
    final McpOAuthToken refreshed = await session.refresh(token);

    expect(refreshed.accessToken, 'access-2');
    expect(refreshed.refreshToken, 'refresh-1');
  });

  test('新进程 refresh：显式传 meta 即可工作', () async {
    final FakeAs fake = await startOAuthFake();
    final McpOAuthSession first = oauthSession();
    final McpOAuthToken token = await first.authorize(
      serverUrl: oauthServerUrl(fake),
      config: oauthConfig(),
      openUrl: answerCallback,
    );
    final McpAuthServerMetadata meta = await discoverAuthServer(
      oauthServerUrl(fake),
    );
    final McpOAuthSession second = oauthSession();

    await second.refresh(token, meta: meta, config: oauthConfig());

    expect(fake.tokenRequests.last['refresh_token'], 'refresh-1');
    expect(fake.tokenRequests.last['client_id'], 'cid');
  });

  test('refresh 失败 → needs_auth，且消息不含令牌', () async {
    final FakeAs fake = await startOAuthFake();
    final McpOAuthSession session = oauthSession();
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

  test('DCR 客户端身份随令牌持久化：新进程无 config 也能刷新', () async {
    final FakeAs fake = await startOAuthFake();
    final McpOAuthSession first = oauthSession();
    final McpOAuthToken token = await first.authorize(
      serverUrl: oauthServerUrl(fake),
      config: const McpOAuthConfig(scope: 'mcp'),
      openUrl: answerCallback,
    );
    expect(token.clientId, 'dcr-client-1');

    final Directory dir = Directory.systemTemp.createTempSync('mcp-oauth-dcr-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final McpOAuthStore store = McpOAuthStore(dir.path);
    await store.save('docs', token);
    final McpOAuthToken loaded = (await store.load('docs'))!;
    final McpAuthServerMetadata meta = await discoverAuthServer(
      oauthServerUrl(fake),
    );
    fake.tokenResponse = <String, Object?>{'access_token': 'access-2'};

    final McpOAuthToken refreshed =
        await oauthSession().refresh(loaded, meta: meta);

    expect(refreshed.accessToken, 'access-2');
    expect(refreshed.clientId, 'dcr-client-1');
    expect(fake.tokenRequests.last['client_id'], 'dcr-client-1');
  });

  test('没有 refresh_token → needs_auth，不发请求', () async {
    final FakeAs fake = await startOAuthFake();
    final McpOAuthSession session = oauthSession();
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
