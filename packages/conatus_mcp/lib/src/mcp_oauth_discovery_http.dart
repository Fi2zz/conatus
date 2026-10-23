part of 'mcp_oauth_discovery.dart';

/// OAuth HTTP 请求：显式超时 + 失败映射（传输错误不漏给调用方）。
Future<http.Response> _post(
  http.Client client,
  Uri uri,
  Map<String, Object?> body,
  Duration timeout,
) async {
  try {
    return await client
        .post(
          uri,
          headers: const <String, String>{
            'content-type': 'application/json',
            'accept': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);
  } on TimeoutException {
    throw McpException(
      'oauth-registration',
      '注册请求超时（${timeout.inMilliseconds}ms）',
    );
  } on http.ClientException catch (error) {
    throw McpException('oauth-registration', '注册请求失败：${error.message}');
  }
}

/// 发现阶段的 GET；超时 / 传输失败返回 `null`（最终收敛为 `oauth-discovery`）。
Future<http.Response?> _get(
  http.Client client,
  Uri uri,
  Duration timeout, {
  bool mcpAccept = false,
}) async {
  try {
    return await client.get(
      uri,
      headers: <String, String>{
        'accept': mcpAccept
            ? 'application/json, text/event-stream'
            : 'application/json',
      },
    ).timeout(timeout);
  } catch (_) {
    return null;
  }
}
