/// 自定义 registry 导入：GET api.json（Bearer token）→ 解析 provider 列表。
///
/// 正文接受 `{"providers": [...]}` 或顶层数组，字段同 [ProviderProfile]。
/// 失败是结果字段，不抛异常。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'provider_profile.dart';

/// 导入结果。
class ProviderImportResult {
  /// 成功：带解析出的 provider 列表。
  const ProviderImportResult.success(this.providers) : error = null;

  /// 失败：带原因。
  const ProviderImportResult.failure(this.error) : providers = const <ProviderProfile>[];

  /// 解析出的 provider（失败时为空）。
  final List<ProviderProfile> providers;

  /// 失败原因（成功时为 `null`）。
  final String? error;

  /// 是否成功。
  bool get isSuccess => error == null;
}

/// 解析 registry 正文；结构不符抛 [FormatException]。
List<ProviderProfile> parseProviderRegistry(String body) {
  final Object? raw = jsonDecode(body);
  final Object? items =
      raw is Map<String, Object?> ? raw['providers'] : raw;
  if (items is! List<Object?>) {
    throw const FormatException('registry 需要 providers 数组或顶层数组');
  }
  return <ProviderProfile>[
    for (final Object? item in items)
      if (item is Map<String, Object?>) ProviderProfile.fromJson(item),
  ];
}

/// 拉取并解析 registry。
Future<ProviderImportResult> fetchProviderRegistry({
  required String url,
  required String token,
  http.Client? client,
}) async {
  final Uri? uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) {
    return const ProviderImportResult.failure('URL 不合法');
  }
  final http.Client resolved = client ?? http.Client();
  try {
    final http.Response response = await resolved.get(
      uri,
      headers: <String, String>{
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      return ProviderImportResult.failure('HTTP ${response.statusCode}');
    }
    final List<ProviderProfile> parsed =
        parseProviderRegistry(utf8.decode(response.bodyBytes));
    return parsed.isEmpty
        ? const ProviderImportResult.failure('registry 里没有 provider')
        : ProviderImportResult.success(parsed);
  } catch (error) {
    return ProviderImportResult.failure('$error');
  } finally {
    if (client == null) resolved.close();
  }
}
