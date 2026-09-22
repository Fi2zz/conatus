/// Exa 搜索 provider（需 API Key）：调用 Exa 的 REST 搜索接口。
///
/// 仅在有 Key 时装配；`buildSearchProviders` 按 [kDefaultSearchOrder] 决定它排
/// 在哪个位置。
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'search_http.dart';
import 'search_types.dart';

/// Exa API Key 的凭据键名。
const String kExaCredentialKey = 'EXA_API_KEY';

/// Exa provider。
class ExaSearchProvider implements SearchProvider {
  ExaSearchProvider({
    required this.apiKey,
    http.Client? client,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 15),
  })  : _client = client ?? http.Client(),
        _endpoint = endpoint ?? Uri.parse('https://api.exa.ai/search');

  /// Exa API Key。
  final String apiKey;

  /// 单次查询超时。
  final Duration timeout;

  final http.Client _client;
  final Uri _endpoint;

  @override
  String get name => 'exa';

  @override
  Future<List<SearchResult>> search(String query, {int limit = 5}) async {
    final http.Response response = await sendWithTimeout(
      _client.post(
        _endpoint,
        headers: <String, String>{
          'content-type': 'application/json',
          'x-api-key': apiKey,
        },
        body: jsonEncode(<String, Object?>{
          'query': query,
          'numResults': limit,
          'contents': <String, Object?>{
            'text': <String, Object?>{'maxCharacters': 500},
          },
        }),
      ),
      timeout: timeout,
      provider: name,
    );
    if (response.statusCode != 200) {
      throw SearchException('exa HTTP ${response.statusCode}');
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const SearchException('exa 返回了非对象 JSON');
    }
    final List<Object?> raw =
        (decoded['results'] as List<Object?>?) ?? const <Object?>[];
    return <SearchResult>[
      for (final Object? item in raw)
        if (item is Map<String, Object?>) _toResult(item),
    ];
  }

  SearchResult _toResult(Map<String, Object?> item) => SearchResult(
        title: item['title'] as String? ?? '',
        url: item['url'] as String? ?? '',
        snippet:
            (item['text'] as String?) ?? (item['summary'] as String?) ?? '',
      );
}
