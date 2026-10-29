/// 网页抓取接缝：把 URL 变成模型可读的正文。
library;

/// 抓取结果的正文形态。
enum FetchedFormat {
  /// 剥离标签后的纯文本。
  text,

  /// 已转换的 markdown。
  markdown,

  /// 原始 HTML。
  html,
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

/// 抓取后端的显式选择。
///
/// [auto] 沿用历史行为（有 Firecrawl Key 就用 Firecrawl，否则裸 HTTP）。
/// 其余取值要求对应的 Key 已配置，缺失时装配期直接失败——静默回退会让人
/// 以为自己在用付费后端。
enum FetchBackend {
  /// 按凭据自动挑选。
  auto,

  /// 裸 HTTP + 本地去标签。
  http,

  /// Firecrawl（需 `FIRECRAWL_API_KEY`）。
  firecrawl,

  /// DeepSeek Fetch（需 `DEEPSEEK_API_KEY`，只产出 markdown）。
  deepseek,
}

/// 抓取接缝。
abstract class WebFetcher {
  /// 抓取 [url]，正文最多 [maxChars] 字符；失败抛 [FetchException]。
  Future<FetchedPage> fetch(
    String url, {
    int maxChars = 20000,
    FetchedFormat format = FetchedFormat.text,
  });
}
