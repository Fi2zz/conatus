/// web 工具：把搜索与抓取能力暴露给模型。
///
/// [WebSearchTool] 走 `ctx.search`（provider 回退由 SearchService 负责）；
/// [FetchUrlTool] 直接 GET 一个 URL 并返回纯文本。二者都是 [ToolRisk.low] 的
/// 只读工具，用 [provideWebTools] 一次性注册到 `ctx.tools`。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:http/http.dart' as http;
import 'fetch/http_fetcher.dart';
import 'search.dart';

/// 联网搜索工具。
class WebSearchTool extends Tool {
  WebSearchTool({required SearchService search, this.defaultLimit = 5})
      : _search = search;

  final SearchService _search;

  /// 未显式传 `limit` 时的默认条数。
  final int defaultLimit;

  @override
  String get name => 'web_search';

  @override
  String get description => '在互联网上搜索，返回结果的标题、链接与摘要。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('query', required: true, description: '搜索关键词'),
        ParamSpec.integer('limit', description: '返回条数'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String query = ctx.str('query');
    final int limit = ctx.integer('limit') ?? defaultLimit;
    final List<SearchResult> results =
        await _search.search(query, limit: limit);
    if (results.isEmpty) {
      return ToolResult.success(
        '未找到与 "$query" 相关的结果',
        value: const <Object?>[],
      );
    }
    final StringBuffer buffer = StringBuffer('搜索 "$query" 的结果：');
    for (int i = 0; i < results.length; i++) {
      final SearchResult result = results[i];
      buffer
        ..write('\n${i + 1}. ${result.title}')
        ..write('\n   ${result.url}');
      if (result.snippet.isNotEmpty) buffer.write('\n   ${result.snippet}');
    }
    return ToolResult.success(
      buffer.toString(),
      value: <Map<String, Object?>>[
        for (final SearchResult result in results) result.toJson(),
      ],
    );
  }
}

/// 抓取网页并返回纯文本。
class FetchUrlTool extends Tool {
  FetchUrlTool({http.Client? client, this.maxChars = 20000})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// 返回文本的最大字符数（超出截断）。
  final int maxChars;

  @override
  String get name => 'fetch_url';

  @override
  String get description => '抓取一个网页并返回其纯文本内容。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('url', required: true, description: 'http(s) 链接'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String raw = ctx.str('url');
    final Uri? uri = Uri.tryParse(raw);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return ToolResult.failure(
        '仅支持 http/https 链接："$raw"',
        error: ToolError('INVALID_URL', 'unsupported url "$raw"'),
      );
    }
    final http.Response response = await _client.get(uri);
    if (response.statusCode != 200) {
      return ToolResult.failure(
        '抓取失败：HTTP ${response.statusCode}',
        error: ToolError('FETCH_FAILED', 'HTTP ${response.statusCode}'),
      );
    }
    final String text = stripHtml(response.body);
    final String content =
        text.length > maxChars ? text.substring(0, maxChars) : text;
    return ToolResult.success(
      content,
      value: <String, Object?>{'url': raw, 'status': response.statusCode},
    );
  }
}

/// 把 web 工具注册到 `ctx.tools`，返回已注册的工具。
///
/// [search] 缺省取上下文的 `'search'` 服务。
List<Tool> provideWebTools(
  Context ctx, {
  SearchService? search,
  http.Client? client,
}) {
  final SearchService service = search ?? ctx.search;
  final List<Tool> registered = <Tool>[
    WebSearchTool(search: service),
    FetchUrlTool(client: client),
  ];
  for (final Tool tool in registered) {
    ctx.effect(() => ctx.tools.register(tool));
  }
  return registered;
}
