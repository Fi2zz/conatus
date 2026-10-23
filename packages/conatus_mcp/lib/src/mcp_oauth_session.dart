/// OAuth 授权码流程（loopback 回调）与刷新。
///
/// 流程：发现授权服务器 → 绑定 `127.0.0.1` 随机端口（或 `callbackPort`）→
/// PKCE + state → 打开授权 URL → 收 `code` → POST 令牌端点。测试用
/// `openUrl` 注入回调，生产缺省交给系统浏览器；授权地址始终经 [log] 输出，
/// SSH / 容器里打不开浏览器也能手动复制。
///
/// 失败一律收敛成 [McpException]：超时 `oauth-timeout`、回调 state 不符
/// `oauth-state`、令牌端点异常 `oauth-token`、需要重新授权 `needs_auth`。
/// **令牌 / code / verifier / client_secret 不进消息与日志。**
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'mcp_oauth_discovery.dart';
import 'mcp_oauth_pkce.dart';
import 'mcp_oauth_types.dart';
import 'mcp_types.dart';

part 'mcp_oauth_session_callback.dart';
part 'mcp_oauth_session_token.dart';

/// 构造授权 URL 所需的本地参数（PKCE 与 state 只在本地保留）。
typedef _AuthorizeRequest = ({
  String clientId,
  Uri redirect,
  PkcePair pkce,
  String state,
  Uri resource,
});

/// 授权流程的上下文（避免私有方法参数膨胀）。
typedef _AuthorizeContext = ({
  McpAuthServerMetadata meta,
  McpOAuthConfig config,
  Uri serverUrl,
  void Function(Uri)? openUrl,
});

/// 一台 MCP server 的 OAuth 会话。
///
/// `authorize` 会缓存本次发现到的元数据与 client，供同实例的 `refresh` 复用；
/// 跨进程刷新时元数据由调用方传入，客户端身份随令牌持久化。
class McpOAuthSession {
  /// 构造。[client] 传入时由调用方关闭；[log] 缺省写 stdout。
  ///
  /// [callbackTimeout] 只约束等待浏览器回调的时间，与 [McpOAuthConfig.timeout]
  /// （单次 HTTP 请求）相互独立。
  McpOAuthSession({
    http.Client? client,
    void Function(String)? log,
    this.callbackTimeout = kMcpOAuthCallbackTimeout,
  })  : _client = client ?? http.Client(),
        _owned = client == null,
        _log = log ?? stdout.writeln;

  final http.Client _client;
  final bool _owned;
  final void Function(String) _log;

  /// 等待用户完成登录的最长时间（缺省 3 分钟）。
  final Duration callbackTimeout;
  McpAuthServerMetadata? _metadata;
  String? _clientId;
  String? _clientSecret;

  /// 关闭自建的 HTTP client；幂等。
  void close() {
    if (_owned) _client.close();
  }

  /// 跑完整授权码流程，返回新令牌；令牌由调用方持久化。
  ///
  /// [openUrl] 缺省用系统浏览器打开；测试注入它以模拟用户点击。
  Future<McpOAuthToken> authorize({
    required Uri serverUrl,
    required McpOAuthConfig config,
    void Function(Uri)? openUrl,
  }) async {
    final McpAuthServerMetadata meta = await discoverAuthServer(
      serverUrl,
      client: _client,
      timeout: config.timeout,
    );
    _adopt(meta, config);
    final HttpServer server = await _bind(config);
    try {
      return await _authorizeOn(server, (
        meta: meta,
        config: config,
        serverUrl: serverUrl,
        openUrl: openUrl,
      ));
    } finally {
      await server.close(force: true);
    }
  }

  /// 用 refresh_token 换新令牌；缺少元数据 / refresh_token 抛 `needs_auth`。
  ///
  /// 客户端身份优先取令牌里持久化的值（DCR 场景），其次取 [config]。
  /// [resource]（RFC 8707）随请求下发，缺省不带。
  Future<McpOAuthToken> refresh(
    McpOAuthToken token, {
    McpAuthServerMetadata? meta,
    McpOAuthConfig? config,
    Uri? resource,
  }) async {
    final Uri? endpoint = (meta ?? _metadata)?.tokenEndpoint;
    final String? refreshToken = token.refreshToken;
    if (endpoint == null || refreshToken == null) {
      throw const McpException('needs_auth', 'MCP OAuth 缺少刷新所需的令牌或端点');
    }
    final String? clientId =
        _resolved(token.clientId ?? _clientId, config?.clientId);
    final String? secret =
        _resolved(token.clientSecret ?? _clientSecret, config?.clientSecret);
    final Map<String, String> body = <String, String>{
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      if (clientId != null) 'client_id': clientId,
      if (secret != null) 'client_secret': secret,
      if (resource != null) 'resource': '$resource',
    };
    final http.Response response = await _postForm(
      _client,
      endpoint,
      body,
      config?.timeout ?? kMcpOAuthTimeout,
    );
    if (response.statusCode != 200) {
      throw McpException('needs_auth', '刷新令牌失败（HTTP ${response.statusCode}）');
    }
    return _parseToken(response, refresh: true).withClient(
      clientId: _resolved(token.clientId ?? _clientId, config?.clientId),
      clientSecret:
          _resolved(token.clientSecret ?? _clientSecret, config?.clientSecret),
    );
  }

  Future<McpOAuthToken> _authorizeOn(
    HttpServer server,
    _AuthorizeContext context,
  ) async {
    final McpAuthServerMetadata meta = context.meta;
    final McpOAuthConfig config = context.config;
    final Uri redirect = Uri.parse('http://127.0.0.1:${server.port}/callback');
    final String clientId = await registerOAuthClient(
      meta,
      redirect,
      client: _client,
      config: config,
    );
    _clientId = clientId;
    final PkcePair pkce = generatePkce();
    final String state = _randomState();
    _openBrowser(
      _authorizeUrl(
        meta.authorizationEndpoint,
        (
          clientId: clientId,
          redirect: redirect,
          pkce: pkce,
          state: state,
          resource: context.serverUrl,
        ),
        config.scope,
      ),
      context.openUrl,
      _log,
    );
    final _Callback callback = await _awaitCode(server, state, callbackTimeout);
    final McpOAuthToken token = await _exchangeOrReject(
      _client,
      context,
      (
        clientId: clientId,
        redirect: redirect,
        code: callback.code,
        verifier: pkce.verifier,
        resource: context.serverUrl
      ),
      callback.request,
    );
    return token.withClient(
        clientId: clientId, clientSecret: config.clientSecret);
  }

  void _adopt(McpAuthServerMetadata meta, McpOAuthConfig config) {
    _metadata = meta;
    _clientId = config.clientId;
    _clientSecret = config.clientSecret;
  }
}
