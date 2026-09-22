/// 把带 HTML 标记的上游文本转成纯文本。
library;

final RegExp _tagRe = RegExp(r'<[^>]+>');

/// 去掉标签、解常见实体并 trim。
///
/// 上游搜索接口（DuckDuckGo 的标题/摘要、Brave 的 `description`）会带
/// `<strong>` 之类的强调标记与实体转义；snippet 会原样进入模型可见输出，
/// 因此在 provider 边界统一清洗。
String stripMarkup(String html) => html
    .replaceAll(_tagRe, '')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&nbsp;', ' ')
    .trim();
