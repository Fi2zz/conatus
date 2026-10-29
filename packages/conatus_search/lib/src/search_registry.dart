/// 搜索源装配：名字 → 工厂表，按顺序构造可用 provider。
library;

import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:http/http.dart' as http;
import 'deepseek_shared.dart';
import 'kimi_shared.dart';
import 'search_brave.dart';
import 'search_deepseek.dart';
import 'search_duckduckgo.dart';
import 'search_exa.dart';
import 'search_exa_mcp.dart';
import 'search_kimi.dart';
import 'search_mcp.dart';
import 'search_parallel.dart';
import 'search_tavily.dart';
import 'search_types.dart';

/// provider 构造所需的依赖（凭据由 [buildSearchProviders] 解析后单独传入）。
class SearchProviderDeps {
  const SearchProviderDeps({
    this.client,
    this.timeout = const Duration(seconds: 15),
  });

  /// HTTP 客户端（测试注入）；缺省由各 provider 自建。
  final http.Client? client;

  /// 单次查询超时。
  final Duration timeout;
}

/// 一个可装配的搜索源。
class SearchProviderSpec {
  const SearchProviderSpec({
    required this.name,
    required this.credentialKey,
    required this.create,
  });

  /// 源名（如 `'tavily'`），用于顺序配置与显式路由。
  final String name;

  /// 凭据键名；空串表示免 Key。
  final String credentialKey;

  /// 用解析出的 [apiKey]（免 Key 源传空串）构造 provider。
  final SearchProvider Function(String apiKey, SearchProviderDeps deps) create;
}

/// 内置搜索源表。
const Map<String, SearchProviderSpec> kSearchProviderSpecs =
    <String, SearchProviderSpec>{
  'tavily': SearchProviderSpec(
    name: 'tavily',
    credentialKey: kTavilyCredentialKey,
    create: _createTavily,
  ),
  'exa': SearchProviderSpec(
    name: 'exa',
    credentialKey: kExaCredentialKey,
    create: _createExa,
  ),
  'brave': SearchProviderSpec(
    name: 'brave',
    credentialKey: kBraveCredentialKey,
    create: _createBrave,
  ),
  'deepseek': SearchProviderSpec(
    name: 'deepseek',
    credentialKey: kDeepSeekCredentialKey,
    create: _createDeepSeek,
  ),
  'kimi': SearchProviderSpec(
    name: 'kimi',
    credentialKey: kKimiCredentialKey,
    create: _createKimi,
  ),
  'duckduckgo': SearchProviderSpec(
    name: 'duckduckgo',
    credentialKey: '',
    create: _createDuckDuckGo,
  ),
  'parallel': SearchProviderSpec(
    name: 'parallel',
    credentialKey: '',
    create: _createParallel,
  ),
  'exa-mcp': SearchProviderSpec(
    name: 'exa-mcp',
    credentialKey: '',
    create: _createExaMcp,
  ),
};

SearchProvider _createTavily(String apiKey, SearchProviderDeps deps) =>
    TavilySearchProvider(
      apiKey: apiKey,
      client: deps.client,
      timeout: deps.timeout,
    );

SearchProvider _createExa(String apiKey, SearchProviderDeps deps) =>
    ExaSearchProvider(
      apiKey: apiKey,
      client: deps.client,
      timeout: deps.timeout,
    );

SearchProvider _createBrave(String apiKey, SearchProviderDeps deps) =>
    BraveSearchProvider(
      apiKey: apiKey,
      client: deps.client,
      timeout: deps.timeout,
    );

SearchProvider _createDeepSeek(String apiKey, SearchProviderDeps deps) =>
    DeepSeekSearchProvider(
      apiKey: apiKey,
      client: deps.client,
      // DeepSeek 检索惯常比单次网页请求慢，装配期给 20s 而不是通用 15s。
      timeout: deps.timeout > const Duration(seconds: 20)
          ? deps.timeout
          : const Duration(seconds: 20),
    );

SearchProvider _createKimi(String apiKey, SearchProviderDeps deps) =>
    KimiSearchProvider(
      apiKey: apiKey,
      client: deps.client,
      // 与 DeepSeek 同口径：检索比单次网页请求慢，装配期至少给 20s。
      timeout: deps.timeout > const Duration(seconds: 20)
          ? deps.timeout
          : const Duration(seconds: 20),
    );

SearchProvider _createDuckDuckGo(String apiKey, SearchProviderDeps deps) =>
    DuckDuckGoSearchProvider(client: deps.client, timeout: deps.timeout);

SearchProvider _createParallel(String apiKey, SearchProviderDeps deps) =>
    McpSearchProvider(
      profile: kParallelSearchProfile,
      client: deps.client,
      timeout: deps.timeout,
    );

SearchProvider _createExaMcp(String apiKey, SearchProviderDeps deps) =>
    McpSearchProvider(
      profile: kExaMcpSearchProfile,
      client: deps.client,
      timeout: deps.timeout,
    );

/// 装配期状态：某个源是否可用及原因。
class SearchSourceStatus {
  const SearchSourceStatus({
    required this.name,
    required this.available,
    this.reason = '',
  });

  /// 源名。
  final String name;

  /// 是否成功装配。
  final bool available;

  /// 不可用原因（可用时为空串）。
  final String reason;
}

/// 装配结果：可用的 provider 与全部源的状态。
class SearchProviderSet {
  const SearchProviderSet({required this.providers, required this.statuses});

  /// 按 order 顺序构造出的 provider。
  final List<SearchProvider> providers;

  /// 与传入的 `order` 同序的状态列表（含被跳过的源）。
  final List<SearchSourceStatus> statuses;
}

/// 缺省搜索源顺序。
///
/// 带 Key 的源在前（配额充足时质量更稳），免 Key 的源兜底；`deepseek` /
/// `kimi` 按成功请求计费，排在带 Key 源的末尾，不抢默认位置。
const List<String> kDefaultSearchOrder = <String>[
  'tavily',
  'exa',
  'brave',
  'deepseek',
  'kimi',
  'parallel',
  'exa-mcp',
  'duckduckgo',
];

/// 按 [order] 构造可用 provider；缺 Key 或名字未知的源跳过并记入 statuses。
///
/// [credentials] 为空时只装配免 Key 的源，缺凭据的源标注为「未提供凭据服务」。
SearchProviderSet buildSearchProviders({
  required List<String> order,
  Credentials? credentials,
  http.Client? client,
}) {
  final SearchProviderDeps deps = SearchProviderDeps(client: client);
  final List<SearchProvider> providers = <SearchProvider>[];
  final List<SearchSourceStatus> statuses = <SearchSourceStatus>[];
  for (final String name in order) {
    final SearchProviderSpec? spec = kSearchProviderSpecs[name];
    if (spec == null) {
      statuses.add(SearchSourceStatus(
        name: name,
        available: false,
        reason: '未知的搜索源',
      ));
      continue;
    }
    if (spec.credentialKey.isEmpty) {
      providers.add(spec.create('', deps));
      statuses.add(SearchSourceStatus(name: name, available: true));
      continue;
    }
    final Credential? credential = credentials?.get(spec.credentialKey);
    if (credential == null) {
      statuses.add(SearchSourceStatus(
        name: name,
        available: false,
        reason: credentials == null ? '未提供凭据服务' : '缺少 ${spec.credentialKey}',
      ));
      continue;
    }
    providers.add(spec.create(credential.value, deps));
    statuses.add(SearchSourceStatus(name: name, available: true));
  }
  return SearchProviderSet(providers: providers, statuses: statuses);
}
