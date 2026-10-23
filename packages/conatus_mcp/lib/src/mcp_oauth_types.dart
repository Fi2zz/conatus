/// MCP 远程传输的 OAuth 2.1 配置与授权服务器元数据。
library;

/// OAuth 发现 / 注册 HTTP 的缺省超时：服务端接受连接却不响应时不得卡死启动。
const Duration kMcpOAuthTimeout = Duration(seconds: 10);

/// 浏览器授权回调的缺省等待上限。
///
/// 与 [kMcpOAuthTimeout]（单次 HTTP 请求）刻意分开：正常登录要输账号、过
/// 二次验证，10 秒必然误杀；这里给足人工操作时间。
const Duration kMcpOAuthCallbackTimeout = Duration(minutes: 3);

/// 单台 MCP server 的 OAuth 配置（`config.toml` 的 `oauth` 键/表）。
///
/// 远程 server 缺省启用（[enabled] 为 `true`）；`oauth = false` 显式关闭。
/// [clientId] / [clientSecret] 是预先注册的客户端凭据，为空时交给动态客户端
/// 注册（DCR）取得。**凭据只用于换取令牌，不得写进日志。**
class McpOAuthConfig {
  /// 直接构造；[enabled] 缺省 `true`。
  const McpOAuthConfig({
    this.enabled = true,
    this.clientId,
    this.clientSecret,
    this.scope,
    this.callbackPort,
    this.timeout = kMcpOAuthTimeout,
  });

  /// 是否对该 server 走 OAuth 流程。
  final bool enabled;

  /// 预注册的客户端 ID；为空时走动态注册。
  final String? clientId;

  /// 预注册的客户端密钥；公共客户端（PKCE）留空。
  final String? clientSecret;

  /// 请求的授权范围（空格分隔）；为空时用授权服务器默认值。
  final String? scope;

  /// 本地回调监听的固定端口；为空时由系统分配。
  final int? callbackPort;

  /// 单次 OAuth HTTP 请求超时（程序化注入；缺省 [kMcpOAuthTimeout]）。
  final Duration timeout;

  /// 是否已有可用的预注册客户端 ID。
  bool get clientConfigured => clientId != null && clientId!.isNotEmpty;
}

/// 授权服务器元数据（RFC 8414 / OpenID Discovery 的交集）。
class McpAuthServerMetadata {
  /// 直接构造；[scopesSupported] 缺省为空。
  const McpAuthServerMetadata({
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    this.registrationEndpoint,
    this.scopesSupported = const <String>[],
  });

  /// 浏览器授权端点。
  final Uri authorizationEndpoint;

  /// 令牌端点（授权码换取与刷新）。
  final Uri tokenEndpoint;

  /// 动态客户端注册端点；`null` 表示服务端不支持 DCR。
  final Uri? registrationEndpoint;

  /// 服务端声明的可用 scope。
  final List<String> scopesSupported;
}

/// 一次授权换来的令牌；**字段就是凭据，不得写进日志或错误消息**。
///
/// [expiresAt] 为 `null` 表示服务端没给 `expires_in`，只能等 401 再刷新。
/// [needsRefresh] 采用「过期前 60 秒」的提前量，避免请求在途中过期。
class McpOAuthToken {
  /// 直接构造。
  const McpOAuthToken({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.scope,
  })  : clientId = null,
        clientSecret = null;

  const McpOAuthToken._({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.scope,
    this.clientId,
    this.clientSecret,
  });

  /// 从令牌端点的 JSON 响应解析；缺 `access_token` 抛 [FormatException]。
  factory McpOAuthToken.fromJson(Map<String, Object?> json) {
    final Object? access = json['access_token'];
    if (access is! String || access.isEmpty) {
      throw const FormatException('令牌 JSON 缺少 access_token');
    }
    final Object? expiresAt = json['expires_at'];
    return McpOAuthToken._(
      accessToken: access,
      refreshToken: _stringOrNull(json['refresh_token']),
      expiresAt: expiresAt is String ? DateTime.tryParse(expiresAt) : null,
      scope: _stringOrNull(json['scope']),
      clientId: _stringOrNull(json['client_id']),
      clientSecret: _stringOrNull(json['client_secret']),
    );
  }

  /// 访问令牌。
  final String accessToken;

  /// 刷新令牌；服务端未下发时为 `null`（过期后只能重新授权）。
  final String? refreshToken;

  /// 绝对过期时刻；`null` 表示未知。
  final DateTime? expiresAt;

  /// 服务端授予的 scope（空格分隔）。
  final String? scope;

  /// 换取该令牌的客户端 ID（DCR 结果或预注册值）。
  ///
  /// 持久化它才能在新进程里刷新：DCR 客户端没有配置文件可依据。
  final String? clientId;

  /// 客户端密钥（公共客户端为 `null`）；同样持久化以保证刷新可用。
  final String? clientSecret;

  /// 附带客户端身份（登录成功后由会话补上；DCR 场景的关键字段）。
  McpOAuthToken withClient({String? clientId, String? clientSecret}) =>
      McpOAuthToken._(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: expiresAt,
        scope: scope,
        clientId: clientId ?? this.clientId,
        clientSecret: clientSecret ?? this.clientSecret,
      );

  /// 距离过期不足 60 秒（或已过期）时为真；没有过期时间时为假。
  bool get needsRefresh {
    final DateTime? expires = expiresAt;
    if (expires == null) return false;
    return !DateTime.now()
        .isBefore(expires.subtract(const Duration(seconds: 60)));
  }

  /// 序列化（存储与测试用）；键名遵循令牌端点响应。
  Map<String, Object?> toJson() => <String, Object?>{
        'access_token': accessToken,
        if (refreshToken != null) 'refresh_token': refreshToken,
        if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
        if (scope != null) 'scope': scope,
        if (clientId != null) 'client_id': clientId,
        if (clientSecret != null) 'client_secret': clientSecret,
      };

  @override
  String toString() => 'McpOAuthToken(accessToken: <redacted>)';
}

String? _stringOrNull(Object? value) =>
    value is String && value.isNotEmpty ? value : null;
