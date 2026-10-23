/// OAuth 授权服务器发现（RFC 9728 / RFC 8414）与动态客户端注册（RFC 7591）。
///
/// 发现顺序：受保护资源元数据 → `authorization_servers[0]` → 授权服务器元数据
/// （先 `oauth-authorization-server`，再回退 `openid-configuration`）；前者
/// 失败时再读目标端点 401 响应 `WWW-Authenticate` 中的 `resource_metadata`。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'mcp_oauth_types.dart';
import 'mcp_types.dart';

const String _protectedResourcePath = '/.well-known/oauth-protected-resource';
const List<String> _authServerPaths = <String>[
  '/.well-known/oauth-authorization-server',
  '/.well-known/openid-configuration',
];

/// 发现 [serverUrl] 对应的授权服务器元数据。
///
/// 只读公开元数据，不接触令牌。全部失败抛 [McpException]（`oauth-discovery`）。
Future<McpAuthServerMetadata> discoverAuthServer(
  Uri serverUrl, {
  http.Client? client,
}) async {
  final http.Client httpClient = client ?? http.Client();
  try {
    final Uri? issuer = await _findIssuer(serverUrl, httpClient);
    if (issuer == null) {
      throw const McpException('oauth-discovery', '未找到 OAuth 授权服务器');
    }
    return await _fetchMetadata(issuer, httpClient);
  } finally {
    if (client == null) httpClient.close();
  }
}

/// 注册（或复用）OAuth 客户端，返回 `client_id`。
///
/// [McpAuthServerMetadata.registrationEndpoint] 非空时走 DCR；否则必须由
/// [config] 提供预注册的 `client_id`，都没有抛 `oauth-no-client`。
Future<String> registerOAuthClient(
  McpAuthServerMetadata meta,
  Uri redirectUri, {
  http.Client? client,
  McpOAuthConfig? config,
}) async {
  final Uri? endpoint = meta.registrationEndpoint;
  if (endpoint == null) {
    final String? configured = config?.clientId;
    if (configured != null && configured.isNotEmpty) return configured;
    throw const McpException(
      'oauth-no-client',
      '授权服务器不支持动态注册，且未配置 client_id',
    );
  }
  final http.Client httpClient = client ?? http.Client();
  try {
    final http.Response response = await httpClient.post(
      endpoint,
      headers: const <String, String>{
        'content-type': 'application/json',
        'accept': 'application/json',
      },
      body: jsonEncode(_registrationBody(redirectUri, config?.scope)),
    );
    final Object? decoded = _tryDecode(response.body);
    final Object? clientId =
        decoded is Map<String, Object?> ? decoded['client_id'] : null;
    if (clientId is String && clientId.isNotEmpty) return clientId;
    throw McpException(
      'oauth-registration',
      '注册端点未返回 client_id（HTTP ${response.statusCode}）',
    );
  } finally {
    if (client == null) httpClient.close();
  }
}

/// DCR 请求体：公共客户端 + 授权码 + 刷新令牌。
Map<String, Object?> _registrationBody(Uri redirectUri, String? scope) =>
    <String, Object?>{
      'client_name': 'conatus',
      'redirect_uris': <String>[redirectUri.toString()],
      'grant_types': <String>['authorization_code', 'refresh_token'],
      'response_types': <String>['code'],
      'token_endpoint_auth_method': 'none',
      if (scope != null && scope.isNotEmpty) 'scope': scope,
    };

Future<Uri?> _findIssuer(Uri serverUrl, http.Client client) async {
  final Uri resourceUri =
      Uri.parse('${serverUrl.origin}$_protectedResourcePath');
  final Uri? direct = _firstAuthServer(await _getJson(client, resourceUri));
  if (direct != null) return direct;
  return _probeUnauthorized(serverUrl, client);
}

/// 读目标端点的 401 `WWW-Authenticate`，跟进其中的 `resource_metadata`。
Future<Uri?> _probeUnauthorized(Uri serverUrl, http.Client client) async {
  final http.Response? response = await _get(client, serverUrl);
  if (response == null || response.statusCode != 401) return null;
  final Uri? metadataUri = _resourceMetadataUri(
    response.headers['www-authenticate'],
    serverUrl,
  );
  if (metadataUri == null) return null;
  return _firstAuthServer(await _getJson(client, metadataUri));
}

Future<McpAuthServerMetadata> _fetchMetadata(
  Uri issuer,
  http.Client client,
) async {
  for (final String path in _authServerPaths) {
    final Uri uri = Uri.parse(
      '${issuer.origin}${_trimSlash(issuer.path)}$path',
    );
    final McpAuthServerMetadata? meta =
        _parseMetadata(await _getJson(client, uri));
    if (meta != null) return meta;
  }
  throw const McpException('oauth-discovery', '授权服务器元数据不可用');
}

McpAuthServerMetadata? _parseMetadata(Map<String, Object?>? json) {
  if (json == null) return null;
  final Uri? authorization = _httpUri(json['authorization_endpoint']);
  final Uri? token = _httpUri(json['token_endpoint']);
  if (authorization == null || token == null) return null;
  return McpAuthServerMetadata(
    authorizationEndpoint: authorization,
    tokenEndpoint: token,
    registrationEndpoint: _httpUri(json['registration_endpoint']),
    scopesSupported: _stringList(json['scopes_supported']),
  );
}

Uri? _firstAuthServer(Map<String, Object?>? json) {
  final Object? raw = json?['authorization_servers'];
  if (raw is! List) return null;
  for (final Object? entry in raw) {
    final Uri? uri = _httpUri(entry);
    if (uri != null) return uri;
  }
  return null;
}

Uri? _resourceMetadataUri(String? challenge, Uri base) {
  if (challenge == null) return null;
  final RegExpMatch? match =
      RegExp(r'resource_metadata\s*=\s*"([^"]+)"').firstMatch(challenge);
  if (match == null) return null;
  return base.resolve(match.group(1)!);
}

List<String> _stringList(Object? raw) => raw is List
    ? <String>[
        for (final Object? e in raw)
          if (e is String) e
      ]
    : const <String>[];

Uri? _httpUri(Object? raw) {
  final Uri? uri = raw is String && raw.isNotEmpty ? Uri.tryParse(raw) : null;
  if (uri == null || uri.host.isEmpty) return null;
  return uri.scheme == 'http' || uri.scheme == 'https' ? uri : null;
}

String _trimSlash(String path) =>
    path.endsWith('/') ? path.substring(0, path.length - 1) : path;

Future<Map<String, Object?>?> _getJson(http.Client client, Uri uri) async {
  final http.Response? response = await _get(client, uri);
  if (response == null || response.statusCode != 200) return null;
  final Object? decoded = _tryDecode(response.body);
  return decoded is Map<String, Object?> ? decoded : null;
}

Future<http.Response?> _get(http.Client client, Uri uri) async {
  try {
    return await client.get(uri, headers: const <String, String>{
      'accept': 'application/json',
    });
  } catch (_) {
    return null;
  }
}

Object? _tryDecode(String body) {
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}
