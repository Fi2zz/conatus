part of 'mcp_oauth_discovery.dart';

/// RFC 8414（路径前插入）与 OIDC（路径后缀）两种元数据地址。
List<Uri> _metadataUris(Uri issuer) {
  final String path = _trimSlash(issuer.path);
  return <Uri>[
    Uri.parse('${issuer.origin}/.well-known/oauth-authorization-server$path'),
    Uri.parse('${issuer.origin}$path/.well-known/openid-configuration'),
  ];
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
  return match == null ? null : base.resolve(match.group(1)!);
}

/// 大小写不敏感取响应头（401 的 `WWW-Authenticate` 可能任意大小写）。
String? _header(Map<String, String> headers, String name) {
  for (final MapEntry<String, String> entry in headers.entries) {
    if (entry.key.toLowerCase() == name) return entry.value;
  }
  return null;
}

List<String> _stringList(Object? raw) => raw is List
    ? <String>[
        for (final Object? entry in raw)
          if (entry is String) entry
      ]
    : const <String>[];

Uri? _httpUri(Object? raw) {
  if (raw is! String) return null;
  final Uri? uri = Uri.tryParse(raw);
  return _httpUrl(uri) ? uri : null;
}

bool _httpUrl(Uri? uri) =>
    uri != null &&
    (uri.scheme == 'http' || uri.scheme == 'https') &&
    uri.host.isNotEmpty;

String _trimSlash(String path) =>
    path.endsWith('/') ? path.substring(0, path.length - 1) : path;
