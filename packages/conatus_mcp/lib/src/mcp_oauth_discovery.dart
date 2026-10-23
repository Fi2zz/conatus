/// OAuth 授权服务器发现（RFC 9728 / RFC 8414）与动态客户端注册（RFC 7591）。
///
/// 发现顺序：受保护资源元数据 → `authorization_servers[0]` → 授权服务器元数据。
/// RFC 8414 的 well-known 插在 issuer 路径**之前**（`/.well-known/
/// oauth-authorization-server<issuer path>`），失败再回退 OIDC 的路径**后缀**
/// 形式（`<issuer path>/.well-known/openid-configuration`）。前者失败时还会
/// 读目标端点 401 响应 `WWW-Authenticate` 中的 `resource_metadata`。
///
/// 所有请求带显式超时；超时 / 传输失败 / 非法 URL 统一收敛成
/// [McpException]（`oauth-discovery` / `oauth-registration`），不把底层
/// `http.ClientException` 漏给调用方。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'mcp_oauth_types.dart';
import 'mcp_types.dart';

part 'mcp_oauth_discovery_http.dart';
part 'mcp_oauth_discovery_metadata.dart';

const String _protectedResourcePath = '/.well-known/oauth-protected-resource';

/// 发现 [serverUrl] 对应的授权服务器元数据。
///
/// [serverUrl] 必须是绝对的 http(s) URL；其余情况立即抛
/// [McpException]（`oauth-discovery`）。只读公开元数据，不接触令牌。
Future<McpAuthServerMetadata> discoverAuthServer(
  Uri serverUrl, {
  http.Client? client,
  Duration timeout = kMcpOAuthTimeout,
}) async {
  if (!_httpUrl(serverUrl)) {
    throw McpException(
      'oauth-discovery',
      'serverUrl 必须是绝对的 http(s) URL：$serverUrl',
    );
  }
  final http.Client httpClient = client ?? http.Client();
  try {
    final Uri? issuer = await _findIssuer(serverUrl, httpClient, timeout);
    if (issuer == null) {
      throw const McpException('oauth-discovery', '未找到 OAuth 授权服务器');
    }
    return await _fetchMetadata(issuer, httpClient, timeout);
  } finally {
    if (client == null) httpClient.close();
  }
}

/// 注册（或复用）OAuth 客户端，返回 `client_id`。
///
/// 配置里已有 `client_id` 时直接复用，不再走 DCR；否则
/// [McpAuthServerMetadata.registrationEndpoint] 非空时注册，为空抛
/// `oauth-no-client`。DCR 的超时 / 传输失败 / 非 2xx / 缺 `client_id`
/// 统一抛 `oauth-registration`。
Future<String> registerOAuthClient(
  McpAuthServerMetadata meta,
  Uri redirectUri, {
  http.Client? client,
  McpOAuthConfig? config,
}) async {
  final String? configured = config?.clientId;
  if (configured != null && configured.isNotEmpty) return configured;
  final Uri? endpoint = meta.registrationEndpoint;
  if (endpoint == null) {
    throw const McpException(
      'oauth-no-client',
      '授权服务器不支持动态注册，且未配置 client_id',
    );
  }
  final http.Client httpClient = client ?? http.Client();
  try {
    final http.Response response = await _post(
      httpClient,
      endpoint,
      _registrationBody(redirectUri, config?.scope),
      config?.timeout ?? kMcpOAuthTimeout,
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw McpException(
        'oauth-registration',
        '注册端点返回 HTTP ${response.statusCode}',
      );
    }
    final Object? decoded = _tryDecode(response.body);
    final Object? clientId =
        decoded is Map<String, Object?> ? decoded['client_id'] : null;
    if (clientId is String && clientId.isNotEmpty) return clientId;
    throw const McpException('oauth-registration', '注册端点未返回 client_id');
  } finally {
    if (client == null) httpClient.close();
  }
}

/// DCR 请求体：公共客户端 + 授权码 + 刷新令牌；**绝不携带 client_secret**。
Map<String, Object?> _registrationBody(Uri redirectUri, String? scope) =>
    <String, Object?>{
      'client_name': 'conatus',
      'redirect_uris': <String>[redirectUri.toString()],
      'grant_types': <String>['authorization_code', 'refresh_token'],
      'response_types': <String>['code'],
      'token_endpoint_auth_method': 'none',
      if (scope != null && scope.isNotEmpty) 'scope': scope,
    };

Future<Uri?> _findIssuer(
  Uri serverUrl,
  http.Client client,
  Duration timeout,
) async {
  final Uri resourceUri =
      Uri.parse('${serverUrl.origin}$_protectedResourcePath');
  final Uri? direct =
      _firstAuthServer(await _getJson(client, resourceUri, timeout));
  if (direct != null) return direct;
  return _probeUnauthorized(serverUrl, client, timeout);
}

/// 读目标端点的 401 `WWW-Authenticate`，跟进其中的 `resource_metadata`。
///
/// 只用 GET 探测（带 MCP 的 `Accept`）：Streamable HTTP 的 GET 仅供服务端
/// 推送，个别实现只接受 POST，会回 405，此时无法从 401 头发现元数据。
Future<Uri?> _probeUnauthorized(
  Uri serverUrl,
  http.Client client,
  Duration timeout,
) async {
  final http.Response? response =
      await _get(client, serverUrl, timeout, mcpAccept: true);
  if (response == null || response.statusCode != 401) return null;
  final Uri? metadataUri = _resourceMetadataUri(
    _header(response.headers, 'www-authenticate'),
    serverUrl,
  );
  if (metadataUri == null) return null;
  return _firstAuthServer(await _getJson(client, metadataUri, timeout));
}

Future<McpAuthServerMetadata> _fetchMetadata(
  Uri issuer,
  http.Client client,
  Duration timeout,
) async {
  for (final Uri uri in _metadataUris(issuer)) {
    final McpAuthServerMetadata? meta =
        _parseMetadata(await _getJson(client, uri, timeout));
    if (meta != null) return meta;
  }
  throw const McpException('oauth-discovery', '授权服务器元数据不可用');
}

Future<Map<String, Object?>?> _getJson(
  http.Client client,
  Uri uri,
  Duration timeout,
) async {
  final http.Response? response = await _get(client, uri, timeout);
  if (response == null || response.statusCode != 200) return null;
  final Object? decoded = _tryDecode(response.body);
  return decoded is Map<String, Object?> ? decoded : null;
}

Object? _tryDecode(String body) {
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}
