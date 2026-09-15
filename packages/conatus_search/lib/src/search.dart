/// search 插件：搜索能力缝（`ctx.search`）+ provider 回退链。
///
/// 服务键 `'search'`。多个 [SearchProvider] 并排注册；[SearchService.search]
/// 按注册顺序尝试，第一个成功即返回，全部失败时抛出汇总错误的
/// [SearchException]。默认 provider 是无需 Key 的 DuckDuckGo，有 Exa Key 时
/// Exa 优先（见 [provideSearch]）。
library;

import 'package:conatus_core/conatus_core.dart';
import 'search_duckduckgo.dart';
import 'search_exa.dart';
import 'search_types.dart';

export 'search_types.dart';

/// 搜索服务：provider 注册表 + 顺序回退。
class SearchService {
  SearchService();

  final List<SearchProvider> _providers = <SearchProvider>[];

  /// 已注册的 provider（按注册顺序）。
  List<SearchProvider> get providers =>
      List<SearchProvider>.unmodifiable(_providers);

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
/// [providers] 显式给出时按序注册；否则新建服务时默认注册
/// `[Exa(apiKey 非空), DuckDuckGo]`——有 Exa Key 时优先，否则只有
/// DuckDuckGo。传入现成的 [search] 且未给 [providers] 时不追加默认 provider。
SearchService provideSearch(
  Context ctx, {
  SearchService? search,
  List<SearchProvider>? providers,
  String? exaApiKey,
}) {
  final SearchService service = search ?? SearchService();
  ctx.provide('search', service);
  final List<SearchProvider> resolved = providers ??
      (search != null
          ? const <SearchProvider>[]
          : <SearchProvider>[
              if (exaApiKey != null && exaApiKey.isNotEmpty)
                ExaSearchProvider(apiKey: exaApiKey),
              DuckDuckGoSearchProvider(),
            ]);
  for (final SearchProvider provider in resolved) {
    ctx.effect(() => service.register(provider));
  }
  return service;
}
