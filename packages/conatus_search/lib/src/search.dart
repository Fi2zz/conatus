/// search 插件：搜索能力缝（`ctx.search`）+ provider 回退链。
///
/// 服务键 `'search'`。多个 [SearchProvider] 并排注册；[SearchService.search]
/// 按注册顺序尝试，第一个成功即返回，全部失败时抛出汇总错误的
/// [SearchException]。默认顺序见 [kDefaultSearchOrder]，缺 Key 的源会被跳过
/// （见 [buildSearchProviders]）。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:http/http.dart' as http;
import 'search_duckduckgo.dart';
import 'search_registry.dart';
import 'search_types.dart';

export 'search_types.dart';

/// 搜索服务：provider 注册表 + 顺序回退。
class SearchService {
  SearchService({
    List<SearchSourceStatus> statuses = const <SearchSourceStatus>[],
  }) : _statuses = List<SearchSourceStatus>.unmodifiable(statuses);

  final List<SearchProvider> _providers = <SearchProvider>[];
  final List<SearchSourceStatus> _statuses;

  /// 已注册的 provider（按注册顺序）。
  List<SearchProvider> get providers =>
      List<SearchProvider>.unmodifiable(_providers);

  /// 装配期状态快照：哪些源可用、哪些被跳过及原因。
  ///
  /// 由 [provideSearch] 填充；动态 [register] 不改变它。
  List<SearchSourceStatus> get statuses => _statuses;

  /// 注册一个 provider。返回撤销函数（幂等）。
  Disposer register(SearchProvider provider) {
    _providers.add(provider);
    return () => _providers.remove(provider);
  }

  /// 查找 provider；未注册返回 `null`。
  SearchProvider? get(String name) {
    for (final SearchProvider provider in _providers) {
      if (provider.name == name) return provider;
    }
    return null;
  }

  /// 查询 [query]：默认顺序回退；给定 [provider] 时只走该 provider。
  ///
  /// 只有 provider 抛异常才试下一个；返回空列表视为成功。
  Future<List<SearchResult>> search(
    String query, {
    int limit = 5,
    String? provider,
  }) async {
    final List<SearchProvider> candidates = provider == null
        ? List<SearchProvider>.of(_providers)
        : <SearchProvider>[];
    if (provider != null) {
      final SearchProvider? found = get(provider);
      if (found == null) {
        throw SearchException('未注册的搜索 provider "$provider"');
      }
      candidates.add(found);
    }
    if (candidates.isEmpty) {
      throw const SearchException('没有可用的搜索 provider');
    }
    final List<String> errors = <String>[];
    for (final SearchProvider candidate in candidates) {
      try {
        return await candidate.search(query, limit: limit);
      } catch (error) {
        errors.add('${candidate.name}: $error');
      }
    }
    throw SearchException('所有搜索 provider 都失败：${errors.join('；')}');
  }
}

/// `ctx.search`：当前上下文可见的搜索服务。
extension SearchContext on Context {
  /// 取当前上下文可见的 [SearchService]（未提供时抛 [StateError]）。
  SearchService get search => require<SearchService>('search');
}

/// 将 [SearchService] 作为 `'search'` 服务提供到上下文。
///
/// 解析顺序：
/// - 显式 [providers] → 按序注册这些实例，忽略 [order]，`statuses` 为空；
/// - 传入现成的 [search] → 不追加任何 provider；
/// - 否则按 [order] 构造：[credentials] 缺省取上下文已提供的 `'credentials'`
///   服务，两者都没有时只装配免 Key 的 DuckDuckGo。
// REASON: 装配入口的参数聚合是既定形态（调用方是进程级 main / 测试），
// 逐个拆开反而增加调用方负担。
SearchService provideSearch(
  Context ctx, {
  List<String> order = kDefaultSearchOrder,
  Credentials? credentials,
  List<SearchProvider>? providers,
  SearchService? search,
  http.Client? client,
}) {
  final SearchProviderSet set = _resolveSearchProviders(
    ctx: ctx,
    order: order,
    credentials: credentials,
    providers: providers,
    existing: search,
    client: client,
  );
  final SearchService service = search ?? SearchService(statuses: set.statuses);
  ctx.provide('search', service);
  for (final SearchProvider provider in set.providers) {
    ctx.effect(() => service.register(provider));
  }
  return service;
}

// REASON: 与 provideSearch 同源的装配参数聚合，逐个拆开只会让调用链更长。
SearchProviderSet _resolveSearchProviders({
  required Context ctx,
  required List<String> order,
  required Credentials? credentials,
  required List<SearchProvider>? providers,
  required SearchService? existing,
  required http.Client? client,
}) {
  if (providers != null) {
    return SearchProviderSet(
      providers: providers,
      statuses: const <SearchSourceStatus>[],
    );
  }
  if (existing != null) {
    return const SearchProviderSet(
      providers: <SearchProvider>[],
      statuses: <SearchSourceStatus>[],
    );
  }
  final Credentials? resolved = credentials ?? ctx.get<Credentials>('credentials');
  if (resolved == null) {
    return _resolveKeylessProviders(order, client);
  }
  return buildSearchProviders(
    order: order,
    credentials: resolved,
    client: client,
  );
}

// REASON: 无凭据回退按 order 装配（只注册免 Key 的 duckduckgo），
// 抽为 helper 守住 _resolveSearchProviders 的函数体行数约束。
SearchProviderSet _resolveKeylessProviders(
  List<String> order,
  http.Client? client,
) {
  final List<SearchProvider> providers = <SearchProvider>[];
  final List<SearchSourceStatus> statuses = <SearchSourceStatus>[];
  for (final String name in order) {
    if (name == 'duckduckgo') {
      providers.add(DuckDuckGoSearchProvider(client: client));
      statuses.add(SearchSourceStatus(name: name, available: true));
    } else {
      statuses.add(SearchSourceStatus(
        name: name,
        available: false,
        reason: '未提供凭据服务',
      ));
    }
  }
  return SearchProviderSet(providers: providers, statuses: statuses);
}
