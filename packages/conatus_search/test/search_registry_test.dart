import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_search/conatus_search.dart';
import 'package:test/test.dart';

void main() {
  test('按 order 构造可用 provider，缺 Key 的跳过并记原因', () {
    final InMemoryCredentials credentials = InMemoryCredentials(
      initial: <String, String>{'TAVILY_API_KEY': 't'},
    );

    final SearchProviderSet set = buildSearchProviders(
      order: <String>['tavily', 'exa', 'brave', 'duckduckgo'],
      credentials: credentials,
    );

    expect(set.providers.map((SearchProvider p) => p.name),
        <String>['tavily', 'duckduckgo']);
    expect((set.providers.first as TavilySearchProvider).apiKey, 't');
    expect(
      set.statuses.map((SearchSourceStatus s) => '${s.name}:${s.available}'),
      <String>['tavily:true', 'exa:false', 'brave:false', 'duckduckgo:true'],
    );
    expect(
      set.statuses.firstWhere((SearchSourceStatus s) => s.name == 'exa').reason,
      '缺少 EXA_API_KEY',
    );
  });

  test('order 决定顺序，未列出的源不参与', () {
    final InMemoryCredentials credentials = InMemoryCredentials(
      initial: <String, String>{'EXA_API_KEY': 'e', 'TAVILY_API_KEY': 't'},
    );

    final SearchProviderSet set = buildSearchProviders(
      order: <String>['exa', 'tavily'],
      credentials: credentials,
    );

    expect(set.providers.map((SearchProvider p) => p.name),
        <String>['exa', 'tavily']);
  });

  test('未知名字跳过并记为不可用', () {
    final SearchProviderSet set = buildSearchProviders(
      order: <String>['nope', 'duckduckgo'],
      credentials: InMemoryCredentials(),
    );

    expect(set.providers.single.name, 'duckduckgo');
    expect(set.statuses.first.reason, '未知的搜索源');
  });

  test('免 Key 的 duckduckgo 始终可用', () {
    final SearchProviderSet set = buildSearchProviders(
      order: <String>['duckduckgo'],
      credentials: InMemoryCredentials(),
    );

    expect(set.providers.single.name, 'duckduckgo');
    expect(set.statuses.single.available, isTrue);
  });

  test('默认顺序是 tavily → exa → brave → duckduckgo', () {
    expect(kDefaultSearchOrder,
        <String>['tavily', 'exa', 'brave', 'duckduckgo']);
  });

  test('内置表覆盖四个源，duckduckgo 免 Key', () {
    expect(kSearchProviderSpecs.keys.toSet(),
        <String>{'tavily', 'exa', 'brave', 'duckduckgo'});
    expect(kSearchProviderSpecs['duckduckgo']!.credentialKey, '');
    expect(kSearchProviderSpecs['tavily']!.credentialKey, 'TAVILY_API_KEY');
  });
}
