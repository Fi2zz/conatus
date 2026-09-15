/// search 插件的词汇：搜索结果、provider 契约与错误。
library;

/// 一条搜索结果。
class SearchResult {
  const SearchResult(
      {required this.title, required this.url, this.snippet = ''});

  /// 结果标题。
  final String title;

  /// 结果链接。
  final String url;

  /// 摘要。
  final String snippet;

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'title': title,
        'url': url,
        'snippet': snippet,
      };

  @override
  String toString() => 'SearchResult($title, $url)';
}

/// 搜索 provider 契约。
///
/// 实现只负责一次查询，失败时抛 [SearchException]；回退链由 `SearchService`
/// 编排。
abstract class SearchProvider {
  /// provider 名（用于诊断与显式路由）。
  String get name;

  /// 查询 [query]，最多返回 [limit] 条结果。
  Future<List<SearchResult>> search(String query, {int limit = 5});
}

/// 搜索失败。
class SearchException implements Exception {
  const SearchException(this.message);

  /// 人可读的失败说明。
  final String message;

  @override
  String toString() => 'SearchException: $message';
}
