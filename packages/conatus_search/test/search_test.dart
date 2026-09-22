import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_search/conatus_search.dart';
import 'package:test/test.dart';

class _FakeProvider implements SearchProvider {
  _FakeProvider(this.name,
      {this.results = const <SearchResult>[], this.fails = false});

  @override
  final String name;
  final List<SearchResult> results;
  final bool fails;

  @override
  Future<List<SearchResult>> search(String query, {int limit = 5}) async {
    if (fails) throw const SearchException('boom');
    return results;
  }
}

const SearchResult _hit =
    SearchResult(title: 'T', url: 'https://example.com', snippet: 'S');

void main() {
  group('SearchService', () {
    test('register / providers / get', () {
      final SearchService service = SearchService();
      final Disposer off = service.register(_FakeProvider('a'));

      expect(
          service.providers.map((SearchProvider p) => p.name), <String>['a']);
      expect(service.get('a'), isNotNull);
      expect(service.get('nope'), isNull);

      off();
      expect(service.providers, isEmpty);
    });

    test('顺序回退：首个成功即返回', () async {
      final SearchService service = SearchService()
        ..register(_FakeProvider('a', fails: true))
        ..register(_FakeProvider('b', results: <SearchResult>[_hit]));

      final List<SearchResult> results = await service.search('q');
      expect(results.single.title, 'T');
    });

    test('指定 provider 只走该 provider', () async {
      final SearchService service = SearchService()
        ..register(_FakeProvider('a', results: <SearchResult>[_hit]))
        ..register(_FakeProvider('b', fails: true));

      expect((await service.search('q', provider: 'a')).single.title, 'T');
      await expectLater(
          service.search('q', provider: 'b'), throwsA(isA<SearchException>()));
      await expectLater(
          service.search('q', provider: 'z'), throwsA(isA<SearchException>()));
    });

    test('无 provider 或全部失败时抛 SearchException', () async {
      await expectLater(
          SearchService().search('q'), throwsA(isA<SearchException>()));

      final SearchService failing = SearchService()
        ..register(_FakeProvider('a', fails: true));
      await expectLater(failing.search('q'), throwsA(isA<SearchException>()));
    });
  });

  group('provideSearch / ctx.search', () {
    test('无凭据服务时只装配免 Key 的 DuckDuckGo', () {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      final SearchService service = provideSearch(ctx);

      expect(service.providers.map((SearchProvider p) => p.name),
          <String>['duckduckgo']);
      expect(identical(ctx.search, service), isTrue);
      expect(
        service.statuses.firstWhere((SearchSourceStatus s) => s.name == 'exa').reason,
        '未提供凭据服务',
      );
    });

    test('无凭据且 order 不含 duckduckgo 时无可用 provider', () {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      final SearchService service =
          provideSearch(ctx, order: <String>['tavily', 'exa']);

      expect(service.providers, isEmpty);
      expect(
        service.statuses.every((SearchSourceStatus s) => !s.available),
        isTrue,
      );
    });

    test('显式 credentials 决定可用源与顺序', () {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      final SearchService service = provideSearch(
        ctx,
        credentials: InMemoryCredentials(
          initial: <String, String>{'EXA_API_KEY': 'e'},
        ),
      );

      expect(service.providers.map((SearchProvider p) => p.name),
          <String>['exa', 'duckduckgo']);
      expect(
        service.statuses.firstWhere((SearchSourceStatus s) => s.name == 'tavily').reason,
        '缺少 TAVILY_API_KEY',
      );
    });

    test('缺省 credentials 取上下文已提供的凭据服务', () {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      provideCredentials(
        ctx,
        credentials:
            InMemoryCredentials(initial: <String, String>{'BRAVE_API_KEY': 'b'}),
      );

      final SearchService service = provideSearch(ctx);

      expect(service.providers.map((SearchProvider p) => p.name),
          <String>['brave', 'duckduckgo']);
    });

    test('order 覆盖默认顺序', () {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      final SearchService service = provideSearch(
        ctx,
        order: <String>['duckduckgo'],
        credentials:
            InMemoryCredentials(initial: <String, String>{'EXA_API_KEY': 'e'}),
      );

      expect(service.providers.single.name, 'duckduckgo');
    });

    test('显式 providers 按序注册，忽略 order，statuses 为空', () {
      final Context ctx = Context.root();
      final SearchService service = provideSearch(ctx,
          providers: <SearchProvider>[_FakeProvider('x')],
          credentials: InMemoryCredentials());

      expect(service.providers.single.name, 'x');
      expect(service.statuses, isEmpty);
      ctx.dispose();
      expect(service.providers, isEmpty);
    });
  });
}
