part of 'mcp_oauth_session.dart';

/// 一次成功的浏览器回调：授权码 + 还握在手里的 HTTP 请求（用于回显结果页）。
typedef _Callback = ({String code, HttpRequest request});

/// 绑定 loopback 回调端口；端口不可用时给出可诊断错误。
Future<HttpServer> _bind(McpOAuthConfig config) async {
  final int? port = config.callbackPort;
  try {
    return await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      port ?? 0,
    );
  } on SocketException {
    throw McpException(
      'oauth-callback',
      port == null ? 'OAuth 回调随机端口不可用' : 'OAuth 回调端口 $port 不可用',
    );
  }
}

/// 等浏览器回调，校验 state，返回 authorization code 与请求句柄。
Future<_Callback> _awaitCode(
  HttpServer server,
  String state,
  Duration timeout,
) async {
  final HttpRequest request = await _nextCallback(server, timeout);
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
  return (code: code, request: request);
}

/// 只接 `/callback`；其他路径回 404，避免浏览器探测/图标请求误当回调。
Future<HttpRequest> _nextCallback(HttpServer server, Duration timeout) {
  final Completer<HttpRequest> completer = Completer<HttpRequest>();
  final Timer timer = Timer(timeout, () {
    if (completer.isCompleted) return;
    completer.completeError(
      const McpException('oauth-timeout', '等待授权回调超时'),
    );
  });
  final StreamSubscription<HttpRequest> subscription = server.listen(
    (HttpRequest request) {
      if (request.uri.path != '/callback') {
        unawaited(
          _reply(request, HttpStatus.notFound, '未找到。')
              .catchError((Object _) {}),
        );
        return;
      }
      if (!completer.isCompleted) completer.complete(request);
    },
  );
  return completer.future.whenComplete(() {
    timer.cancel();
    unawaited(subscription.cancel());
  });
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

/// 交换令牌成功后才回显成功页；失败回错误页再抛出。
Future<McpOAuthToken> _exchangeOrReject(
  http.Client client,
  _AuthorizeContext context,
  _CodeGrant grant,
  HttpRequest request,
) async {
  try {
    final McpOAuthToken token = await _exchangeCode(
      client,
      context.meta.tokenEndpoint,
      context.config,
      grant,
    );
    await _reply(request, HttpStatus.ok, '授权完成，可以关闭此窗口。');
    return token;
  } on Object {
    await _reply(request, HttpStatus.badRequest, '授权失败，请回到终端重试。');
    rethrow;
  }
}

/// 始终先输出授权地址（SSH / 容器里浏览器打不开也能手动复制）。
void _openBrowser(
  Uri url,
  void Function(Uri)? opener,
  void Function(String) log,
) {
  log('请在浏览器打开以下地址完成 MCP 授权：$url');
  try {
    if (opener != null) {
      opener(url);
      return;
    }
    String command = 'xdg-open';
    if (Platform.isMacOS) command = 'open';
    if (Platform.isWindows) command = 'explorer';
    Process.run(command, <String>['$url']).ignore();
  } on Object {
    log('无法自动打开浏览器，请手动复制上面的地址。');
  }
}
