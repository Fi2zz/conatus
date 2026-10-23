part of 'mcp_oauth_session.dart';

/// 绑定 loopback 回调端口；固定端口被占用时给出可诊断错误。
Future<HttpServer> _bind(McpOAuthConfig config) async {
  try {
    return await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      config.callbackPort ?? 0,
    );
  } on SocketException {
    throw McpException(
      'oauth-callback',
      'OAuth 回调端口 ${config.callbackPort ?? 0} 不可用',
    );
  }
}

/// 等浏览器回调，校验 state，返回 authorization code。
Future<String> _awaitCode(
  HttpServer server,
  String state,
  Duration timeout,
) async {
  try {
    final HttpRequest request = await server.first.timeout(timeout);
    final Map<String, String> query = request.uri.queryParameters;
    final String? error = query['error'];
    if (error != null) {
      return _reject(request, 'needs_auth', '授权被拒绝（$error）');
    }
    if (query['state'] != state) {
      return _reject(request, 'oauth-state', '授权回调 state 不匹配');
    }
    final String? code = query['code'];
    if (code == null || code.isEmpty) {
      return _reject(request, 'oauth-token', '授权回调缺少 code');
    }
    await _reply(request, HttpStatus.ok, '授权完成，可以关闭此窗口。');
    return code;
  } on TimeoutException {
    throw const McpException('oauth-timeout', '等待授权回调超时');
  }
}

/// 回一个错误页并抛错（浏览器端不会悬着等连接超时）。
Future<Never> _reject(
  HttpRequest request,
  String code,
  String message,
) async {
  await _reply(request, HttpStatus.badRequest, '授权失败，请回到终端重试。');
  throw McpException(code, message);
}

Future<void> _reply(HttpRequest request, int status, String text) async {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.html;
  request.response.write('<meta charset="utf-8"><p>$text</p>');
  await request.response.close();
}

/// 高熵 state（16 字节 base64url，无填充）。
String _randomState() {
  final Random random = Random.secure();
  final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}
