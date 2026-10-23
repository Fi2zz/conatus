/// OAuth 授权码流程（loopback 回调）与刷新。
///
/// 流程：发现授权服务器 → 绑定 `127.0.0.1` 随机端口（或 `callbackPort`）→
/// PKCE + state → 打开授权 URL → 收 `code` → POST 令牌端点。测试用
/// `openUrl` 注入回调，生产缺省交给系统浏览器。
///
/// 失败一律收敛成 [McpException]：超时 `oauth-timeout`、回调 state 不符
/// `oauth-state`、令牌端点异常 `oauth-token`、需要重新授权 `needs_auth`。
/// **令牌 / code / verifier 不进消息与日志。**
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
});

/// 一台 MCP server 的 OAuth 会话。
///
/// `authorize` 会缓存本次发现到的元数据与 client，供同实例的 `refresh` 复用；
/// 跨进程刷新时由调用方把 [McpAuthServerMetadata] 传给 `refresh`。
class McpOAuthSession {
  /// 构造。[client] 传入时由调用方关闭。
  McpOAuthSession({http.Client? client})
      : _client = client ?? http.Client(),
        _owned = client == null;

  final http.Client _client;
  final bool _owned;
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
      return await _authorizeOn(server, meta, config, openUrl);
    } finally {
      await server.close(force: true);
    }
  }

  /// 用 refresh_token 换新令牌；缺少元数据 / refresh_token 抛 `needs_auth`。
  ///
  /// [meta] / [config] 供跨进程调用（装配期从文件读出令牌后刷新）。
  Future<McpOAuthToken> refresh(
    McpOAuthToken token, {
    McpAuthServerMetadata? meta,
    McpOAuthConfig? config,
  }) async {
    final Uri? endpoint = (meta ?? _metadata)?.tokenEndpoint;
    final String? refreshToken = token.refreshToken;
    if (endpoint == null || refreshToken == null) {
      throw const McpException('needs_auth', 'MCP OAuth 缺少刷新所需的令牌或端点');
    }
    final Map<String, String> body = _refreshBody(token, refreshToken, config);
    final http.Response response = await _postForm(
      _client,
      endpoint,
      body,
      config?.timeout ?? kMcpOAuthTimeout,
    );
    if (response.statusCode != 200) {
      throw McpException('needs_auth', '刷新令牌失败（HTTP ${response.statusCode}）');
    }
    return _parseToken(response, refresh: true);
  }

  Map<String, String> _refreshBody(
    McpOAuthToken token,
    String refreshToken,
    McpOAuthConfig? config,
  ) {
    final String? clientId = _resolved(_clientId, config?.clientId);
    final String? secret = _resolved(_clientSecret, config?.clientSecret);
    return <String, String>{
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      if (clientId != null) 'client_id': clientId,
      if (secret != null) 'client_secret': secret,
    };
  }

  Future<McpOAuthToken> _authorizeOn(
    HttpServer server,
    McpAuthServerMetadata meta,
    McpOAuthConfig config,
    void Function(Uri)? openUrl,
  ) async {
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
    final _AuthorizeRequest request = (
      clientId: clientId,
      redirect: redirect,
      pkce: pkce,
      state: state,
    );
    _open(_authorizeUrl(meta.authorizationEndpoint, request, config.scope),
        openUrl);
    final String code = await _awaitCode(server, state, config.timeout);
    return _exchangeCode(
      _client,
      meta.tokenEndpoint,
      config,
      (
        clientId: clientId,
        redirect: redirect,
        code: code,
        verifier: pkce.verifier
      ),
    );
  }

  void _adopt(McpAuthServerMetadata meta, McpOAuthConfig config) {
    _metadata = meta;
    _clientId = config.clientId;
    _clientSecret = config.clientSecret;
  }

  void _open(Uri url, void Function(Uri)? opener) {
    if (opener != null) {
      opener(url);
      return;
    }
    String command = 'xdg-open';
    if (Platform.isMacOS) command = 'open';
    if (Platform.isWindows) command = 'explorer';
    Process.run(command, <String>['$url']).ignore();
  }
}
