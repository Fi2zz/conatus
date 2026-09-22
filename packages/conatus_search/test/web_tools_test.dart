import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_search/conatus_search.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

class _StubProvider implements SearchProvider {
  _StubProvider(this.results);

  final List<SearchResult> results;

  @override
  String get name => 'stub';

  @override
  Future<List<SearchResult>> search(String query, {int limit = 5}) async =>
      results;
}

class _FailingProvider implements SearchProvider {
  @override
  String get name => 'failing';

  @override
  Future<List<SearchResult>> search(String query, {int limit = 5}) async =>
      throw const SearchException('boom');
}

class _StubFetcher implements WebFetcher {
  _StubFetcher(this.page);

  final FetchedPage page;

  @override
  Future<FetchedPage> fetch(String url, {int maxChars = 20000}) async => page;
}

class _FailingFetcher implements WebFetcher {
  @override
  Future<FetchedPage> fetch(String url, {int maxChars = 20000}) async =>
      throw const FetchException('boom');
}

ToolContext _context(Map<String, Object?> args) =>
    ToolContext(ToolCall(name: 't', arguments: args));

void main() {
  group('WebSearchTool', () {
    test('格式化搜索结果与规范值', () async {
      final SearchService service = SearchService()
        ..register(_StubProvider(<SearchResult>[
          const SearchResult(title: '标题', url: 'https://e.com', snippet: '摘要'),
        ]));
      final WebSearchTool tool = WebSearchTool(search: service);

      final ToolResult result =
          await tool.call(_context(<String, Object?>{'query': '天气'}));

      expect(result.isError, isFalse);
      expect(result.content, contains('标题'));
      expect(result.content, contains('https://e.com'));
      expect(
          (result.value! as List<Object?>).single, isA<Map<String, Object?>>());
      expect(tool.name, 'web_search');
      expect(tool.riskLevel, ToolRisk.low);
      expect(tool.params.first.name, 'query');
    });

    test('无结果返回提示', () async {
      final WebSearchTool tool = WebSearchTool(
        search: SearchService()
          ..register(_StubProvider(const <SearchResult>[])),
      );

      final ToolResult result =
          await tool.call(_context(<String, Object?>{'query': 'x'}));

      expect(result.content, contains('未找到'));
    });

    test('全部 provider 失败 → SEARCH_UNAVAILABLE 且列出未配置的源', () async {
      final SearchService service = SearchService(
        statuses: const <SearchSourceStatus>[
          SearchSourceStatus(name: 'tavily', available: true),
          SearchSourceStatus(
              name: 'exa', available: false, reason: '缺少 EXA_API_KEY'),
        ],
      )..register(_FailingProvider());
      final WebSearchTool tool = WebSearchTool(search: service);

      final ToolResult result =
          await tool.call(_context(<String, Object?>{'query': 'x'}));

      expect(result.isError, isTrue);
      expect(result.error!.code, 'SEARCH_UNAVAILABLE');
      expect(result.content, contains('无法联网：所有搜索源都不可用。'));
      expect(result.content, contains('boom'));
      expect(result.content, contains('未配置的搜索源：exa（缺少 EXA_API_KEY）'));
    });

    test('没有不可用源时不追加未配置段落', () async {
      final SearchService service = SearchService()
        ..register(_FailingProvider());
      final WebSearchTool tool = WebSearchTool(search: service);

      final ToolResult result =
          await tool.call(_context(<String, Object?>{'query': 'x'}));

      expect(result.content, contains('无法联网'));
      expect(result.content, isNot(contains('未配置的搜索源')));
    });
  });

  group('FetchUrlTool', () {
    test('抓取并去标签', () async {
      final FetchUrlTool tool = FetchUrlTool(
        client: MockClient((http.Request request) async => http.Response(
              '<html><body><script>bad()</script><p>Hello &amp; world</p></body></html>',
              200,
            )),
      );

      final ToolResult result =
          await tool.call(_context(<String, Object?>{'url': 'https://e.com'}));

      expect(result.content, 'Hello & world');
      expect(result.isError, isFalse);
    });

    test('非 200 → FETCH_FAILED', () async {
      final FetchUrlTool tool = FetchUrlTool(
        client:
            MockClient((http.Request request) async => http.Response('', 404)),
      );

      final ToolResult result =
          await tool.call(_context(<String, Object?>{'url': 'https://e.com'}));

      expect(result.isError, isTrue);
      expect(result.error!.code, 'FETCH_FAILED');
    });

    test('非 http(s) 链接 → INVALID_URL', () async {
      final FetchUrlTool tool = FetchUrlTool();

      final ToolResult result =
          await tool.call(_context(<String, Object?>{'url': 'ftp://e.com'}));

      expect(result.error!.code, 'INVALID_URL');
    });

    test('注入 WebFetcher 时走注入实现', () async {
      final FetchUrlTool tool = FetchUrlTool(
        fetcher: _StubFetcher(
          const FetchedPage(
            url: 'https://e.com',
            content: '# 注入的正文',
            format: FetchedFormat.markdown,
          ),
        ),
      );

      final ToolResult result =
          await tool.call(_context(<String, Object?>{'url': 'https://e.com'}));

      expect(result.content, '# 注入的正文');
      expect((result.value! as Map<String, Object?>)['format'], 'markdown');
    });

    test('fetcher 抛 FetchException → FETCH_FAILED 且文案带“无法联网”', () async {
      final FetchUrlTool tool = FetchUrlTool(fetcher: _FailingFetcher());

      final ToolResult result =
          await tool.call(_context(<String, Object?>{'url': 'https://e.com'}));

      expect(result.isError, isTrue);
      expect(result.error!.code, 'FETCH_FAILED');
      expect(result.content, contains('无法联网'));
      expect(result.content, contains('boom'));
    });
  });

  test('stripHtml 去块、去标签、解码实体', () {
    expect(stripHtml('<style>x{}</style><div>a &lt;b&gt; c</div>'), 'a <b> c');
  });

  group('provideWebTools', () {
    test('注册两个工具并随上下文释放撤销', () {
      final Context ctx = Context.root();
      provideSearch(ctx);
      final ToolRegistry tools = provideTools(ctx);

      final List<Tool> registered = provideWebTools(ctx);

      expect(registered, hasLength(2));
      expect(tools.names, containsAll(<String>['web_search', 'fetch_url']));
      ctx.dispose();
      expect(tools.names, isEmpty);
    });

    test('有 FIRECRAWL_API_KEY 时 fetch_url 走 Firecrawl', () {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      provideSearch(ctx);
      provideTools(ctx);

      final List<Tool> registered = provideWebTools(
        ctx,
        credentials: InMemoryCredentials(
          initial: <String, String>{'FIRECRAWL_API_KEY': 'fc'},
        ),
      );

      final FetchUrlTool fetch = registered.whereType<FetchUrlTool>().single;
      expect(fetch.fetcher, isA<FirecrawlFetcher>());
    });

    test('无 Firecrawl Key 时 fetch_url 走 HttpFetcher', () {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      provideSearch(ctx);
      provideTools(ctx);

      final List<Tool> registered =
          provideWebTools(ctx, credentials: InMemoryCredentials());

      final FetchUrlTool fetch = registered.whereType<FetchUrlTool>().single;
      expect(fetch.fetcher, isA<HttpFetcher>());
    });
  });
}
