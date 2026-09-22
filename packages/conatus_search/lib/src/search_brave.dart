/// Brave Search provider（需 API Key）：调用 Brave 的 web search 接口。
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'search_http.dart';
import 'search_markup.dart';
import 'search_types.dart';

/// Brave Search API Key 的凭据键名。
const String kBraveCredentialKey = 'BRAVE_API_KEY';

/// Brave 单次查询的结果数上限（上游限制）。
const int kBraveMaxCount = 20;

/// Brave provider。
class BraveSearchProvider implements SearchProvider {
  BraveSearchProvider({
    required this.apiKey,
    http.Client? client,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 15),
  })  : _client = client ?? http.Client(),
        _endpoint = endpoint ??
            Uri.parse('https://api.search.brave.com/res/v1/web/search');

  /// Brave Search API Key。
  final String apiKey;

  /// 单次查询超时。
  final Duration timeout;

  final http.Client _client;
  final Uri _endpoint;

  @override
  String get name => 'brave';

  @override
  Future<List<SearchResult>> search(String query, {int limit = 5}) async {
    final Uri uri = _endpoint.replace(queryParameters: <String, String>{
      'q': query,
      'count': '${limit.clamp(1, kBraveMaxCount)}',
    });
    final http.Response response = await sendWithTimeout(
      _client.get(
        uri,
        headers: <String, String>{
          'accept': 'application/json',
          'x-subscription-token': apiKey,
        },
      ),
      timeout: timeout,
      provider: name,
    );
    if (response.statusCode != 200) {
      throw SearchException('brave HTTP ${response.statusCode}');
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const SearchException('brave 返回了非对象 JSON');
    }
    final Object? web = decoded['web'];
    if (web is! Map<String, Object?>) {
      return const <SearchResult>[];
    }
    final List<Object?> raw =
        (web['results'] as List<Object?>?) ?? const <Object?>[];
    return <SearchResult>[
      for (final Object? item in raw)
        if (item is Map<String, Object?>)
          SearchResult(
            title: item['title'] as String? ?? '',
            url: item['url'] as String? ?? '',
            snippet: stripMarkup(item['description'] as String? ?? ''),
          ),
    ];
  }
}
