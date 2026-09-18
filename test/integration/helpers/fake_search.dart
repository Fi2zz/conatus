/// 假搜索 Provider：按查询词返回预设结果，或对指定查询抛错。
library;

import 'package:conatus_search/conatus_search.dart';

class FakeSearchProvider implements SearchProvider {
  FakeSearchProvider({Map<String, List<SearchResult>>? results})
      : _results = results ?? <String, List<SearchResult>>{};

  final Map<String, List<SearchResult>> _results;

  /// 记录收到的查询词，供断言。
  final List<String> queries = <String>[];

  /// 视为失败的查询词（抛 [SearchException]）。
  final Set<String> failingQueries = <String>{};

  @override
  String get name => 'fake-search';

  @override
  Future<List<SearchResult>> search(String query, {int limit = 5}) async {
    queries.add(query);
    if (failingQueries.contains(query)) {
      throw SearchException('查询失败: $query');
    }
    return _results[query] ?? const <SearchResult>[];
  }
}

/// 快捷构造一条搜索结果。
SearchResult searchResult(String title, String url, {String snippet = ''}) =>
    SearchResult(title: title, url: url, snippet: snippet);
