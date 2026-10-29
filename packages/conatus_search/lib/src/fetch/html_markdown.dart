/// HTML → Markdown：基于 html 包做结构化转换（标题、段落、链接、列表、代码）。
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// 把 HTML 转成可读 Markdown；不追求完整 HTML5 语义。
String htmlToMarkdown(String html) {
  final DocumentFragment fragment = html_parser.parseFragment(html);
  final StringBuffer buffer = StringBuffer();
  _renderNodes(fragment.nodes, buffer);
  return _clean(buffer.toString());
}

void _renderNodes(List<Node> nodes, StringBuffer out) {
  for (final Node node in nodes) {
    if (node is Text) {
      out.write(_collapse(node.text));
      continue;
    }
    if (node is! Element) continue;
    final String tag = node.localName ?? '';
    switch (tag) {
      case 'script' || 'style' || 'noscript':
        break;
      case 'br':
        out.write('\n');
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final int level = int.parse(tag.substring(1));
        out.write('\n\n${'#' * level} ');
        _renderNodes(node.nodes, out);
        out.write('\n\n');
      case 'p' || 'div' || 'section' || 'article' || 'header' || 'footer':
        out.write('\n');
        _renderNodes(node.nodes, out);
        out.write('\n');
      case 'ul' || 'ol':
        out.write('\n');
        _renderNodes(node.nodes, out);
        out.write('\n');
      case 'li':
        out.write('\n- ');
        _renderNodes(node.nodes, out);
      case 'a':
        out.write('[');
        _renderNodes(node.nodes, out);
        final String href = node.attributes['href'] ?? '';
        out.write(href.isEmpty ? ']' : ']($href)');
      case 'strong' || 'b':
        out.write('**');
        _renderNodes(node.nodes, out);
        out.write('**');
      case 'em' || 'i':
        out.write('*');
        _renderNodes(node.nodes, out);
        out.write('*');
      case 'code':
        out.write('`');
        out.write(_collapse(node.text));
        out.write('`');
      case 'pre':
        out.write('\n```\n');
        out.write(node.text.trimRight());
        out.write('\n```\n');
      case 'img':
        final String alt = node.attributes['alt'] ?? '';
        final String src = node.attributes['src'] ?? '';
        if (src.isNotEmpty) out.write('![$alt]($src)');
      default:
        _renderNodes(node.nodes, out);
    }
  }
}

String _collapse(String text) => text.replaceAll(RegExp(r'[ \t\r\n]+'), ' ');

String _clean(String text) {
  final List<String> lines = <String>[];
  for (final String raw in text.split('\n')) {
    final String line = raw.trimRight();
    if (line.isEmpty && (lines.isEmpty || lines.last.isEmpty)) continue;
    lines.add(line);
  }
  return lines.join('\n').trim();
}
