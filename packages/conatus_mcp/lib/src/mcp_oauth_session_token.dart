part of 'mcp_oauth_session.dart';

/// 授权码换令牌所需的一组本地参数。
typedef _CodeGrant = ({
  String clientId,
  Uri redirect,
  String code,
  String verifier,
});

/// POST 令牌端点并把响应解析成 [McpOAuthToken]。
Future<McpOAuthToken> _exchangeCode(
  http.Client client,
  Uri endpoint,
  McpOAuthConfig config,
  _CodeGrant grant,
) async {
  final http.Response response = await _postForm(
    client,
    endpoint,
    _codeBody(config, grant),
    config.timeout,
  );
  if (response.statusCode != 200) {
    throw McpException('oauth-token', '令牌端点返回 HTTP ${response.statusCode}');
  }
  return _parseToken(response, refresh: false);
}

Future<http.Response> _postForm(
  http.Client client,
  Uri endpoint,
  Map<String, String> body,
  Duration timeout,
) async {
  try {
    return await client
        .post(
          endpoint,
          headers: const <String, String>{
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'application/json',
          },
          body: body,
        )
        .timeout(timeout);
  } on TimeoutException {
    throw const McpException('oauth-timeout', '令牌端点请求超时');
  } on http.ClientException {
    throw const McpException('oauth-token', '令牌端点不可用');
  }
}

/// 解析令牌响应；[refresh] 为真时失败码是 `needs_auth`。
///
/// 响应正文只用来取字段，**任何情况下都不拼进错误消息**。
McpOAuthToken _parseToken(http.Response response, {required bool refresh}) {
  final String code = refresh ? 'needs_auth' : 'oauth-token';
  try {
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('令牌响应不是对象');
    }
    return McpOAuthToken.fromJson(_withExpiry(decoded));
  } on FormatException {
    throw McpException(code, '令牌端点返回非法响应');
  }
}

/// 令牌端点给的是相对秒数；落盘前换算成绝对时刻。
Map<String, Object?> _withExpiry(Map<String, Object?> json) {
  final Object? expiresIn = json['expires_in'];
  if (expiresIn is! num) return json;
  return <String, Object?>{
    ...json,
    'expires_at': DateTime.now()
        .add(Duration(seconds: expiresIn.toInt()))
        .toIso8601String(),
  };
}

Map<String, String> _codeBody(McpOAuthConfig config, _CodeGrant grant) {
  final String? secret = _resolved(null, config.clientSecret);
  return <String, String>{
    'grant_type': 'authorization_code',
    'code': grant.code,
    'redirect_uri': '${grant.redirect}',
    'client_id': grant.clientId,
    'code_verifier': grant.verifier,
    if (secret != null) 'client_secret': secret,
  };
}

Uri _authorizeUrl(
  Uri endpoint,
  _AuthorizeRequest request,
  String? scope,
) =>
    endpoint.replace(
      queryParameters: <String, String>{
        ...endpoint.queryParameters,
        'response_type': 'code',
        'client_id': request.clientId,
        'redirect_uri': '${request.redirect}',
        'code_challenge': request.pkce.challenge,
        'code_challenge_method': 'S256',
        'state': request.state,
        if (scope != null && scope.isNotEmpty) 'scope': scope,
      },
    );

String? _resolved(String? stored, String? configured) {
  final String? value =
      configured == null || configured.isEmpty ? stored : configured;
  return value == null || value.isEmpty ? null : value;
}
