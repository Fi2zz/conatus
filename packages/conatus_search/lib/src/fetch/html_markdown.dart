/// 轻量 HTML → Markdown 转换：覆盖标题、段落、链接、列表、粗斜体、代码。
library;

/// 把 HTML 转成可读 Markdown；不追求完整 HTML5 语义。
String htmlToMarkdown(String html) {
  String out = html
      .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '');
  for (int level = 1; level <= 6; level++) {
    final String hashes = '#' * level;
    out = out.replaceAllMapped(
      RegExp('<h$level[^>]*>([\\s\\S]*?)</h$level>', caseSensitive: false),
      (Match match) => '\n\n$hashes ${match.group(1)!.trim()}\n\n',
    );
  }
  out = out
      .replaceAllMapped(
        RegExp(
          r'''<a[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)</a>''',
          caseSensitive: false,
        ),
        (Match match) => '[${match.group(2)!.trim()}](${match.group(1)})',
      )
      .replaceAll(RegExp(r'<(strong|b)[^>]*>([\s\S]*?)</\1>', caseSensitive: false), r'**$2**')
      .replaceAll(RegExp(r'<(em|i)[^>]*>([\s\S]*?)</\1>', caseSensitive: false), r'*$2*')
      .replaceAll(RegExp(r'<code[^>]*>([\s\S]*?)</code>', caseSensitive: false), r'`$1`')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n- ')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|section|article|li|ul|ol|tr)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n[ \t]+'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  return out;
}
