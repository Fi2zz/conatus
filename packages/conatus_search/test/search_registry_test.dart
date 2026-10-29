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

  test('无凭据服务时免 Key 源（含 MCP 源）照样装配', () {
    final SearchProviderSet set = buildSearchProviders(
      order: <String>['tavily', 'parallel', 'exa-mcp', 'duckduckgo'],
    );

    expect(
      set.providers.map((SearchProvider p) => p.name),
      <String>['parallel', 'exa-mcp', 'duckduckgo'],
    );
    expect(
      set.statuses.first.reason,
      '未提供凭据服务',
    );
  });

  test('默认顺序把免 Key 源排在带 Key 源之后', () {
    expect(
      kDefaultSearchOrder,
      <String>[
        'tavily',
        'exa',
        'brave',
        'deepseek',
        'parallel',
        'exa-mcp',
        'duckduckgo',
      ],
    );
  });

  test('内置表覆盖七个源，免 Key 的三个 credentialKey 为空', () {
    expect(kSearchProviderSpecs.keys.toSet(), <String>{
      'tavily',
      'exa',
      'brave',
      'deepseek',
      'duckduckgo',
      'parallel',
      'exa-mcp',
    });
    expect(kSearchProviderSpecs['tavily']!.credentialKey, 'TAVILY_API_KEY');
    expect(kSearchProviderSpecs['deepseek']!.credentialKey, 'DEEPSEEK_API_KEY');
    for (final String name in <String>['duckduckgo', 'parallel', 'exa-mcp']) {
      expect(kSearchProviderSpecs[name]!.credentialKey, '', reason: name);
    }
  });

  test('DeepSeek 复用 DEEPSEEK_API_KEY：配了 LLM 就不必另配搜索 Key', () {
    final SearchProviderSet set = buildSearchProviders(
      order: <String>['deepseek'],
      credentials: InMemoryCredentials(
        initial: <String, String>{'DEEPSEEK_API_KEY': 'sk'},
      ),
    );

    expect(set.providers.single.name, 'deepseek');
    expect((set.providers.single as DeepSeekSearchProvider).apiKey, 'sk');
    expect(set.statuses.single.available, isTrue);
  });

  test('缺 DEEPSEEK_API_KEY 时跳过并给出键名', () {
    final SearchProviderSet set = buildSearchProviders(
      order: <String>['deepseek'],
      credentials: InMemoryCredentials(),
    );

    expect(set.providers, isEmpty);
    expect(set.statuses.single.reason, '缺少 DEEPSEEK_API_KEY');
  });
}
