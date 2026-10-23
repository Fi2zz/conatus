/// MCP 远程传输的 OAuth 2.1 配置与授权服务器元数据。
library;

/// OAuth 发现 / 注册 HTTP 的缺省超时：服务端接受连接却不响应时不得卡死启动。
const Duration kMcpOAuthTimeout = Duration(seconds: 10);

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
