/// 网页抓取接缝：把 URL 变成模型可读的正文。
library;

/// 抓取结果的正文形态。
enum FetchedFormat {
  /// 剥离标签后的纯文本。
  text,

  /// 已转换的 markdown。
  markdown,
}

/// 一次抓取的结果。
class FetchedPage {
  const FetchedPage({
    required this.url,
    required this.content,
    required this.format,
  });

  /// 抓取的 URL。
  final String url;

  /// 正文（已按 `maxChars` 截断）。
  final String content;

  /// 正文形态。
  final FetchedFormat format;
}

/// 抓取失败。
class FetchException implements Exception {
  const FetchException(this.message);

  /// 人可读的失败说明。
  final String message;

  @override
  String toString() => 'FetchException: $message';
}

/// 抓取接缝。
abstract class WebFetcher {
  /// 抓取 [url]，正文最多 [maxChars] 字符；失败抛 [FetchException]。
  Future<FetchedPage> fetch(String url, {int maxChars = 20000});
}
