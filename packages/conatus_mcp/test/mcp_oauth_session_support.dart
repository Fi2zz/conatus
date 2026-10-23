/// OAuth 会话测试共用：本地假 AS、配置与模拟浏览器回调。
library;

import 'dart:async';
import 'dart:io';

import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'mcp_oauth_fake_as.dart';

/// 启动假 AS 并登记清理。
Future<FakeAs> startOAuthFake() async {
  final FakeAs fake = await FakeAs.start();
  addTearDown(fake.close);
  return fake;
}

/// 带上固定 client_id / scope 的配置。
McpOAuthConfig oauthConfig({
  Duration timeout = const Duration(seconds: 5),
}) =>
    McpOAuthConfig(clientId: 'cid', scope: 'mcp', timeout: timeout);

Uri oauthServerUrl(FakeAs fake) => Uri.parse('${fake.origin}/mcp');

/// 建一个默认静默日志、自动清理的会话。
McpOAuthSession oauthSession({
  Duration callbackTimeout = kMcpOAuthCallbackTimeout,
  void Function(String)? log,
}) {
  final McpOAuthSession session = McpOAuthSession(
    callbackTimeout: callbackTimeout,
    log: log ?? (String _) {},
  );
  addTearDown(session.close);
  return session;
}

/// 模拟浏览器回调：带上授权 URL 里的 state，向 loopback 发 code。
void answerCallback(
  Uri authorizeUrl, {
  String code = 'code-1',
  String? state,
  String? error,
}) {
  final Uri callback = Uri.parse(
    authorizeUrl.queryParameters['redirect_uri']!,
  ).replace(
    queryParameters: <String, String>{
      if (error != null) 'error': error else 'code': code,
      'state': state ?? authorizeUrl.queryParameters['state']!,
    },
  );
  unawaited(http.get(callback));
}

Matcher oauthFailure(String code) => throwsA(
      isA<McpException>().having((McpException e) => e.code, 'code', code),
    );

Future<int> freePort() async {
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  final int port = server.port;
  await server.close(force: true);
  return port;
}
