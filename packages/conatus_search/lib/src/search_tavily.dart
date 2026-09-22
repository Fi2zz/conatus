/// Tavily 搜索 provider（需 API Key）：面向 LLM 的搜索接口。
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'search_http.dart';
import 'search_types.dart';

/// Tavily API Key 的凭据键名。
const String kTavilyCredentialKey = 'TAVILY_API_KEY';

/// Tavily 单次查询的结果数上限（上游限制）。
const int kTavilyMaxResults = 20;

/// Tavily provider。
class TavilySearchProvider implements SearchProvider {
  TavilySearchProvider({
    required this.apiKey,
    http.Client? client,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 15),
  })  : _client = client ?? http.Client(),
        _endpoint = endpoint ?? Uri.parse('https://api.tavily.com/search');

  /// Tavily API Key。
  final String apiKey;

  /// 单次查询超时。
  final Duration timeout;

  final http.Client _client;
  final Uri _endpoint;

  @override
  String get name => 'tavily';

  @override
  Future<List<SearchResult>> search(String query, {int limit = 5}) async {
    final http.Response response = await sendWithTimeout(
      _client.post(
        _endpoint,
        headers: <String, String>{
          'content-type': 'application/json',
          'authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(<String, Object?>{
          'query': query,
          'max_results': limit.clamp(1, kTavilyMaxResults),
          'search_depth': 'basic',
        }),
      ),
      timeout: timeout,
      provider: name,
    );
    if (response.statusCode != 200) {
      throw SearchException('tavily HTTP ${response.statusCode}');
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const SearchException('tavily 返回了非对象 JSON');
    }
    final List<Object?> raw =
        (decoded['results'] as List<Object?>?) ?? const <Object?>[];
    return <SearchResult>[
      for (final Object? item in raw)
        if (item is Map<String, Object?>)
          SearchResult(
            title: item['title'] as String? ?? '',
            url: item['url'] as String? ?? '',
            snippet: item['content'] as String? ?? '',
          ),
    ];
  }
}
