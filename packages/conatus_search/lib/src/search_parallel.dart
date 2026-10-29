/// Parallel 托管 MCP 搜索源（免 Key）：`https://mcp.parallel.ai/mcp`。
///
/// 与 opencode 的 `websearch` 同一路子——把厂商托管的 MCP 端点当搜索后端用，
/// 不需要用户自备 API Key。选它作为首选 keyless 源的理由是**返回结构化结果**
/// （`structuredContent.results[]`），解析不依赖文本格式。
library;

import 'search_mcp.dart';
import 'search_types.dart';

/// Parallel 端点。
const String kParallelMcpEndpoint = 'https://mcp.parallel.ai/mcp';

/// Parallel 远端搜索工具名。
const String kParallelSearchTool = 'web_search';

/// Parallel 的摘要长度上限：单条摘录可能上千字符，逐条截断以免撑爆上下文。
const int kParallelSnippetLimit = 600;

/// Parallel 搜索源描述。
final McpSearchProfile kParallelSearchProfile = McpSearchProfile(
  name: 'parallel',
  endpoint: kParallelMcpEndpoint,
  tool: kParallelSearchTool,
  buildArguments: (String query, int limit) => <String, Object?>{
    // 工具要求 objective 是「原子化的目标」，query 是 3-6 词的短查询；
    // 只有一个入参时复用它，两个槽位语义都还能接受。
    'objective': query,
    'search_queries': <String>[query],
  },
  decode: decodeParallelResults,
);

/// 把 Parallel 的 `tools/call` 结果解成搜索结果。
List<SearchResult> decodeParallelResults(Map<String, Object?> result) {
  final Map<String, Object?> structured = mcpStructuredResult(result) ??
      const <String, Object?>{};
  final Object? raw = structured['results'];
  if (raw is! List) return const <SearchResult>[];
  return <SearchResult>[
    for (final Object? item in raw)
      if (item is Map<String, Object?>) _toResult(item),
  ];
}

SearchResult _toResult(Map<String, Object?> item) => SearchResult(
      title: item['title'] as String? ?? '',
      url: item['url'] as String? ?? '',
      snippet: _snippet(item['excerpts']),
    );

/// 把 `excerpts[]` 拼成一段摘要并截断。
String _snippet(Object? excerpts) {
  final String joined = switch (excerpts) {
    final List<Object?> list => list.whereType<String>().join('\n'),
    final String text => text,
    _ => '',
  };
  final String trimmed = joined.trim();
  if (trimmed.length <= kParallelSnippetLimit) return trimmed;
  return '${trimmed.substring(0, kParallelSnippetLimit)}…';
}
