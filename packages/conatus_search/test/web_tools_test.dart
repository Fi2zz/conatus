import 'package:conatus_core/conatus_core.dart';
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
  });
}
