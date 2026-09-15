import 'package:conatus_core/conatus_core.dart';
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
    test('默认只有 DuckDuckGo', () {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      final SearchService service = provideSearch(ctx);

      expect(service.providers.map((SearchProvider p) => p.name),
          <String>['duckduckgo']);
      expect(identical(ctx.search, service), isTrue);
    });

    test('有 Exa Key 时 Exa 优先', () {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      final SearchService service = provideSearch(ctx, exaApiKey: 'k');

      expect(service.providers.map((SearchProvider p) => p.name),
          <String>['exa', 'duckduckgo']);
    });

    test('显式 providers 按序注册，随上下文释放撤销', () {
      final Context ctx = Context.root();
      final SearchService service =
          provideSearch(ctx, providers: <SearchProvider>[_FakeProvider('x')]);

      expect(service.providers.single.name, 'x');
      ctx.dispose();
      expect(service.providers, isEmpty);
    });
  });
}
