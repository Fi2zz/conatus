/// web 工具：把搜索与抓取能力暴露给模型。
///
/// [WebSearchTool] 走 `ctx.search`（provider 回退由 SearchService 负责）；
/// [FetchUrlTool] 经 [WebFetcher] 抓取正文（缺省裸 http，配了 Firecrawl Key 时
/// 走 Firecrawl）。二者都是 [ToolRisk.low] 的只读工具，用 [provideWebTools]
/// 一次性注册到 `ctx.tools`。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:http/http.dart' as http;
import 'fetch/fetcher.dart';
import 'fetch/firecrawl_fetcher.dart';
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

/// 抓取网页并返回正文。
class FetchUrlTool extends Tool {
  FetchUrlTool({
    WebFetcher? fetcher,
    http.Client? client,
    this.maxChars = 20000,
  }) : _fetcher = fetcher ?? HttpFetcher(client: client);

  final WebFetcher _fetcher;

  /// 返回正文的最大字符数（超出截断）。
  final int maxChars;

  /// 当前使用的抓取后端（供测试与诊断）。
  WebFetcher get fetcher => _fetcher;

  @override
  String get name => 'fetch_url';

  @override
  String get description => '抓取一个网页并返回其正文内容。';

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
    final FetchedPage page;
    try {
      page = await _fetcher.fetch(raw, maxChars: maxChars);
    } on FetchException catch (error) {
      return ToolResult.failure(
        '无法联网：抓取 $raw 失败。${error.message}',
        error: ToolError('FETCH_FAILED', error.message),
      );
    }
    return ToolResult.success(
      page.content,
      value: <String, Object?>{'url': page.url, 'format': page.format.name},
    );
  }
}

/// 把 web 工具注册到 `ctx.tools`，返回已注册的工具。
///
/// [search] 缺省取上下文的 `'search'` 服务；[fetcher] 显式给出时优先，
/// 否则有 `FIRECRAWL_API_KEY` 时用 [FirecrawlFetcher]，都没有则 [HttpFetcher]。
// REASON: 装配入口的参数聚合是既定形态（调用方是进程级 main / 测试），
// 逐个拆开反而增加调用方负担。
List<Tool> provideWebTools(
  Context ctx, {
  SearchService? search,
  WebFetcher? fetcher,
  Credentials? credentials,
  http.Client? client,
}) {
  final SearchService service = search ?? ctx.search;
  final List<Tool> registered = <Tool>[
    WebSearchTool(search: service),
    FetchUrlTool(
      fetcher: fetcher ?? _resolveFetcher(ctx, credentials, client),
    ),
  ];
  for (final Tool tool in registered) {
    ctx.effect(() => ctx.tools.register(tool));
  }
  return registered;
}

WebFetcher _resolveFetcher(
  Context ctx,
  Credentials? credentials,
  http.Client? client,
) {
  final Credentials? resolved =
      credentials ?? ctx.get<Credentials>('credentials');
  final Credential? key = resolved?.get(kFirecrawlCredentialKey);
  if (key == null) return HttpFetcher(client: client);
  return FirecrawlFetcher(apiKey: key.value, client: client);
}
