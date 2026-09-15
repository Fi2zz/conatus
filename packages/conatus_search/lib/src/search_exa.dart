/// Exa 搜索 provider（需 API Key）：调用 Exa 的 REST 搜索接口。
///
/// 仅在有 Key 时注册；[provideSearch] 会在 Key 非空时把它排在 DuckDuckGo 之前，
/// 从而“有 Key 时优先”。
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'search_types.dart';

/// Exa provider。
class ExaSearchProvider implements SearchProvider {
  ExaSearchProvider({
    required this.apiKey,
    http.Client? client,
    Uri? endpoint,
  })  : _client = client ?? http.Client(),
        _endpoint = endpoint ?? Uri.parse('https://api.exa.ai/search');

  /// Exa API Key。
  final String apiKey;

  final http.Client _client;
  final Uri _endpoint;

  @override
  String get name => 'exa';

  @override
  Future<List<SearchResult>> search(String query, {int limit = 5}) async {
    final http.Response response = await _client.post(
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
