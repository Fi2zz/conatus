/// Exa 托管 MCP 搜索源（免 Key）：`https://mcp.exa.ai/mcp`。
///
/// 作为 Parallel 之后的第二选择。它的结果**只有文本**（`structuredContent`
/// 为 null），形如：
///
/// ```text
/// Title: Sound null safety
/// URL: https://dart.dev/null-safety
/// Published: 2026-02-26T00:00:00.000Z
/// Author: N/A
/// Highlights:
/// 正文……
/// ```
///
/// 因此解析按「`Title:` / `URL:` 成对出现」识别结果块，其余行并入上一条的
/// 摘要。上游若改版只会让结果变少或摘要不理想，不会抛错——避免一条格式变化
/// 就把整条回退链打断。
library;

import 'search_mcp.dart';
import 'search_types.dart';

/// Exa 端点。
const String kExaMcpEndpoint = 'https://mcp.exa.ai/mcp';

/// Exa 远端搜索工具名。
const String kExaMcpSearchTool = 'web_search_exa';

/// 单条摘要的字符上限。
const int kExaMcpSnippetLimit = 600;

/// Exa 搜索源描述。
final McpSearchProfile kExaMcpSearchProfile = McpSearchProfile(
  name: 'exa-mcp',
  endpoint: kExaMcpEndpoint,
  tool: kExaMcpSearchTool,
  buildArguments: (String query, int limit) => <String, Object?>{
    // 两个字段都是必填；query 承载关键词，objective 复述同一句（规范要求
    // objective 描述「这一轮想拿什么」，单入参下无法更具体）。
    'query': query,
    'objective': query,
    'numResults': limit,
  },
  decode: decodeExaMcpResults,
);

/// 从 Exa 的文本结果里解析条目。
List<SearchResult> decodeExaMcpResults(Map<String, Object?> result) {
  final List<String> lines = mcpResultText(result).split('\n');
  final List<SearchResult> results = <SearchResult>[];
  String? title;
  String? url;
  final StringBuffer snippet = StringBuffer();

  void flush() {
    if (url == null) return;
    results.add(SearchResult(
      title: title ?? url!,
      url: url!,
      snippet: _clip(snippet.toString()),
    ));
    title = null;
    url = null;
    snippet.clear();
  }

  for (final String line in lines) {
    final String trimmed = line.trim();
    if (trimmed.startsWith('Title: ')) {
      // 新的 Title 意味着上一条已结束（URL 行是本块的边界）。
      if (url != null) flush();
      title = trimmed.substring(7).trim();
      continue;
    }
    if (trimmed.startsWith('URL: ')) {
      url = trimmed.substring(5).trim();
      continue;
    }
    if (url == null) continue;
    if (_isMetadataLine(trimmed)) continue;
    snippet.write(line);
    snippet.write('\n');
  }
  flush();
  return results;
}

/// 结果块头部那些对摘要无价值的行。
bool _isMetadataLine(String line) =>
    line.isEmpty ||
    line.startsWith('Published: ') ||
    line.startsWith('Author: ') ||
    line == 'Highlights:';

String _clip(String raw) {
  final String text = raw.trim();
  if (text.length <= kExaMcpSnippetLimit) return text;
  return '${text.substring(0, kExaMcpSnippetLimit)}…';
}
