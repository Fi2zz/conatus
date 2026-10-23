part of 'mcp_transport_base.dart';

/// 带 OAuth 鉴权与 401 单次重试的 HTTP 请求执行器。
///
/// 每次请求前取一次鉴权头并合并进基础头；收到 401 时调用刷新钩子一次，带新
/// 头重试。仍 401（或没有刷新钩子）抛 `needs_auth`——调用方据此提示重新登录。
class _AuthedHttp {
  _AuthedHttp({
    required this.client,
    required this.baseHeaders,
    this.authHeaders,
    this.refreshAuth,
  });

  final http.Client client;
  final Map<String, String> baseHeaders;
  final Future<Map<String, String>> Function()? authHeaders;
  final Future<Map<String, String>> Function()? refreshAuth;

  Future<http.Response> post(Uri target, String body) async {
    http.Response response = await _post(target, body);
    final Map<String, String>? refreshed =
        response.statusCode == 401 ? await _refresh() : null;
    if (refreshed != null) {
      response = await _post(target, body, override: refreshed);
    }
    if (response.statusCode == 401) throw _needsAuth();
    return response;
  }

  Future<http.StreamedResponse> stream(Uri target) async {
    http.StreamedResponse response = await _stream(target);
    if (response.statusCode != 401) return response;
    // 丢弃旧 401 正文再重试，避免连接/字节流悬着。
    await response.stream.drain<void>();
    final Map<String, String>? refreshed = await _refresh();
    if (refreshed != null) {
      response = await _stream(target, override: refreshed);
    }
    if (response.statusCode == 401) throw _needsAuth();
    return response;
  }

  Future<http.Response> _post(
    Uri target,
    String body, {
    Map<String, String>? override,
  }) async =>
      client.post(
        target,
        headers: await _headers(override),
        body: body,
      );

  Future<http.StreamedResponse> _stream(
    Uri target, {
    Map<String, String>? override,
  }) async {
    final Map<String, String> headers = await _headers(override);
    headers.remove('Content-Type');
    headers['Accept'] = 'text/event-stream';
    return client.send(http.Request('GET', target)..headers.addAll(headers));
  }

  /// 基础头 + 本次鉴权头；鉴权头覆盖同名基础头。
  Future<Map<String, String>> _headers([
    Map<String, String>? override,
  ]) async {
    final Map<String, String> extra =
        override ?? await authHeaders?.call() ?? const <String, String>{};
    return <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      ...baseHeaders,
      ...extra,
    };
  }

  /// 取刷新后的鉴权头；没有刷新钩子返回 `null`。
  ///
  /// 刷新失败统一收敛成 `needs_auth`，不把底层异常（可能含响应细节）外漏。
  Future<Map<String, String>?> _refresh() async {
    final Future<Map<String, String>> Function()? refresher = refreshAuth;
    if (refresher == null) return null;
    try {
      return await refresher();
    } on McpException {
      rethrow;
    } on Object {
      throw const McpException('needs_auth', 'MCP server 令牌刷新失败');
    }
  }

  McpException _needsAuth() =>
      const McpException('needs_auth', 'MCP server 需要重新授权（HTTP 401）');
}
