/// DuckDuckGo 搜索 provider（无需 Key）：抓取 html 端点并解析结果。
///
/// HTML 解析是尽力而为的最佳努力（上游结构可能变化），但 provider 失败会抛
/// [SearchException]，由 [SearchService] 回退到下一个 provider。解析器
/// [parseDuckDuckGoHtml] 独立可测。
library;

import 'package:http/http.dart' as http;
import 'search_types.dart';

/// 常见的浏览器 UA，降低被拦概率。
const String _userAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0 Safari/537.36';

final RegExp _anchorRe = RegExp(
  r'<a[^>]*class="result__a"[^>]*>(.*?)</a>',
  dotAll: true,
  caseSensitive: false,
);
final RegExp _snippetRe = RegExp(
  r'<a[^>]*class="result__snippet"[^>]*>(.*?)</a>',
  dotAll: true,
  caseSensitive: false,
);
final RegExp _hrefRe = RegExp(r'href="([^"]*)"', caseSensitive: false);
final RegExp _tagRe = RegExp(r'<[^>]+>');

/// DuckDuckGo provider。
class DuckDuckGoSearchProvider implements SearchProvider {
  DuckDuckGoSearchProvider({http.Client? client, Uri? endpoint})
      : _client = client ?? http.Client(),
        _endpoint = endpoint ?? Uri.parse('https://html.duckduckgo.com/html/');

  final http.Client _client;
  final Uri _endpoint;

  @override
  String get name => 'duckduckgo';

  @override
  Future<List<SearchResult>> search(String query, {int limit = 5}) async {
    final Uri uri =
        _endpoint.replace(queryParameters: <String, String>{'q': query});
    final http.Response response = await _client.get(
      uri,
      headers: <String, String>{'user-agent': _userAgent},
    );
    if (response.statusCode != 200) {
      throw SearchException('duckduckgo HTTP ${response.statusCode}');
    }
    return parseDuckDuckGoHtml(response.body, limit: limit);
  }
}

/// 解析 DuckDuckGo html 端点结果为搜索结果。
List<SearchResult> parseDuckDuckGoHtml(String html, {int limit = 5}) {
  final List<RegExpMatch> anchors = _anchorRe.allMatches(html).toList();
  final List<RegExpMatch> snippets = _snippetRe.allMatches(html).toList();
  final List<SearchResult> results = <SearchResult>[];
  for (int i = 0; i < anchors.length && results.length < limit; i++) {
    final RegExpMatch anchor = anchors[i];
    final String href = _hrefRe.firstMatch(anchor.group(0)!)?.group(1) ?? '';
    final String url = _decodeHref(href);
    final String title = _plainText(anchor.group(1) ?? '');
    if (url.isEmpty || title.isEmpty) continue;
    final String snippet =
        i < snippets.length ? _plainText(snippets[i].group(1) ?? '') : '';
    results.add(SearchResult(title: title, url: url, snippet: snippet));
  }
  return results;
}

String _decodeHref(String href) {
  if (href.isEmpty) return href;
  final String absolute = href.startsWith('//') ? 'https:$href' : href;
  final Uri? uri = Uri.tryParse(absolute);
  final String? real = uri?.queryParameters['uddg'];
  return real ?? absolute;
}

String _plainText(String html) => html
    .replaceAll(_tagRe, '')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&nbsp;', ' ')
    .trim();
