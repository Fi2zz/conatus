# conatus_search 多 provider 搜索路由 — 设计

日期：2026-09-22
状态：已确认，待实施
范围：`packages/conatus_search`（包内能力），不含 `conatus_code` 接线

## 背景

`conatus_search` 是搜索能力缝：`SearchProvider` 抽象 + `SearchService`（顺序回退）
+ `WebSearchTool` / `FetchUrlTool`。当前只有 DuckDuckGo（HTML 抓取、免 Key）与
Exa（REST、需 Key）两个源，且存在三个具体问题：

1. **凭据未接入凭据服务**。`provideSearch(ctx, {exaApiKey: String?})` 是裸参数，
   `bin/conatus_code.dart` 直接读 `Platform.environment['EXA_API_KEY']`，与仓库
   「Key 统一经 `conatus_credentials` 解析、不直接读环境变量」的既定方向不符。
2. **顺序不可配置**。默认顺序硬编码在 `provideSearch` 内部（有 Exa Key 则 Exa
   优先，否则 DuckDuckGo），调用方无法按名字指定。
3. **失败信息笼统**。所有源都失败时，模型只看到聚合异常文本，分不清「没配 Key」
   与「网络挂了」，也没有补救提示。

另外 `fetch_url` 只有裸 http + `stripHtml`，遇到 JS 渲染或反爬页面拿不到正文。

## 目标

- 新增 Tavily、Brave 两个 HTTP 搜索源，与 Exa、DuckDuckGo 并列可选。
- 凭据统一走 `conatus_credentials`，provider 顺序按名字列表装配，缺 Key 自动跳过。
- Firecrawl 作为 `fetch_url` 的可选后端，把网页转成 markdown。
- 搜索全失败时给出明确的「无法联网」失败文案，含每家原因与补救提示。

## 范围

### 包含

- `conatus_search` 包内的 provider 扩充、凭据接缝、装配 API、抓取接缝、失败文案。
- `conatus_code` 与根 example 中 `provideSearch` 调用的**必要签名适配**。

### 不包含（后续 spec）

- **provider 内置搜索**（Anthropic / OpenAI Responses / DashScope 的服务端
  `web_search`，及 `server_tool_use` / `web_search_tool_result` 解析）。需要先改
  `conatus_llm`：当前 `_chatTools` / `_responsesTools` 把工具无条件改写成
  `type:'function'`，responses 流式解析丢弃 `web_search_call` 帧，
  `LlmResult` / `LlmStreamEvent` 也没有 citations 承载字段。
- **`conatus_code` 接线**：`[websearch]` 配置段、`/websearch-auth`、
  `/websearch-order` 命令、沙箱说明。
- **MCP 外部搜索**：本设计全部走进程内 HTTP，不接 `conatus_mcp`。
- **并发 fan-out / 结果合并去重 / 路由组**。
- **域名级沙箱网络白名单**：现有 `network_allowlist` 匹配命令行前缀，
  `workspace_sandbox` 只提供布尔 `--no-net`；且搜索走主进程 http，本就不受沙箱约束。
- **空结果回退**：见「决策记录」。

## 决策记录

| 决策点 | 结论 | 理由 |
|---|---|---|
| 降级层形态 | 进程内 HTTP provider，不走 MCP | 复用现有 `SearchProvider` 接缝；无子进程、无新依赖 |
| 装配方式 | 名字驱动工厂 + `Credentials` | 为后续 `/websearch-order` 铺路；Key 统一经凭据服务 |
| provider 集合 | Tavily、Brave 作搜索源；Firecrawl 作抓取后端 | Firecrawl 的差异化价值在抓取（markdown、JS 渲染），不是搜索 |
| 回退条件 | **只有抛错才试下一个**，空结果视为成功 | 用户选择维持现状；避免真实无结果时白跑并消耗付费配额 |
| fail-closed | 工具层明确失败文案 | 模型拿到具体原因，不会编造答案 |
| 多 provider 路由 | 不纳入 | 现有顺序 fallback 与 `search(query, provider: '名字')` 已够用 |
| 默认顺序 | `tavily → exa → brave → duckduckgo` | Tavily 专为 LLM 设计且有免费额度；缺 Key 会跳过，对只配 Exa 的用户行为不变 |

**已知限制**：provider 返回空列表不算失败，因此 DuckDuckGo 被反爬时（HTTP 200 但
解析出 0 条）回退链仍会在此截断。这是本设计有意保留的语义，不是缺陷。

## 架构

### 模块结构

```
packages/conatus_search/lib/src/
  search_types.dart              # 不变：SearchResult / SearchProvider / SearchException
  search.dart                    # SearchService 语义不变；provideSearch 签名改造
  search_registry.dart           # 新增：名字 → SearchProviderSpec 表 + buildSearchProviders
  search_tavily.dart             # 新增：TavilySearchProvider
  search_brave.dart              # 新增：BraveSearchProvider
  search_duckduckgo.dart         # 不变
  search_exa.dart                # 微调：接入统一 timeout
  fetch/fetcher.dart             # 新增：WebFetcher 抽象 + FetchedPage + FetchedFormat
  fetch/http_fetcher.dart        # 新增：默认抓取实现（stripHtml 逻辑迁入）
  fetch/firecrawl_fetcher.dart   # 新增：Firecrawl /v1/scrape → markdown
  web_tools.dart                 # 改造：失败文案 + fetcher 注入
```

`pubspec.yaml` 新增依赖 `conatus_credentials`（对齐 `conatus_llm` 的凭据模式）。

barrel `lib/conatus_search.dart` 相应扩充：新增导出 `TavilySearchProvider`、
`BraveSearchProvider`、`SearchProviderSpec`、`SearchProviderDeps`、
`SearchProviderSet`、`SearchSourceStatus`、`buildSearchProviders`、
`kSearchProviderSpecs`、`kDefaultSearchOrder`、各 `k*CredentialKey` 常量、
`WebFetcher`、`FetchedPage`、`FetchedFormat`、`HttpFetcher`、`FirecrawlFetcher`；
`stripHtml` 的导出改指 `src/fetch/http_fetcher.dart`（符号名不变）。

### 凭据键常量

```dart
const String kTavilyCredentialKey = 'TAVILY_API_KEY';
const String kExaCredentialKey = 'EXA_API_KEY';
const String kBraveCredentialKey = 'BRAVE_API_KEY';
const String kFirecrawlCredentialKey = 'FIRECRAWL_API_KEY';
```

DuckDuckGo 的 `credentialKey` 为空串，表示免 Key。

### 装配 API

```dart
/// provider 构造所需的依赖。
class SearchProviderDeps {
  const SearchProviderDeps({
    required this.credentials,
    this.client,
    this.timeout = const Duration(seconds: 15),
  });
  final Credentials credentials;
  final http.Client? client;   // 测试注入
  final Duration timeout;
}

/// 一个可装配的搜索源。
class SearchProviderSpec {
  const SearchProviderSpec({
    required this.name,
    required this.credentialKey,   // 空串 = 免 Key
    required this.create,
  });
  final String name;
  final String credentialKey;
  final SearchProvider Function(String apiKey, SearchProviderDeps deps) create;
}

/// 内置搜索源表，四个条目。`duckduckgo` 的 credentialKey 为空串（免 Key），
/// 其余三个见上方常量；`create` 把 apiKey 与 deps（client / timeout）交给具体
/// provider 构造函数。
const Map<String, SearchProviderSpec> kSearchProviderSpecs = <String, SearchProviderSpec>{
  'tavily': SearchProviderSpec(
    name: 'tavily',
    credentialKey: kTavilyCredentialKey,
    create: (String apiKey, SearchProviderDeps deps) => TavilySearchProvider(
      apiKey: apiKey,
      client: deps.client,
      timeout: deps.timeout,
    ),
  ),
  // exa / brave / duckduckgo 三个条目同构，create 分别指向各自的构造函数；
  // duckduckgo 忽略传入的 apiKey。
};

/// 装配期状态：某个源是否可用及原因。
class SearchSourceStatus {
  const SearchSourceStatus({required this.name, required this.available, this.reason = ''});
  final String name;
  final bool available;
  final String reason;   // 如 '缺少 EXA_API_KEY'
}

/// 装配结果。
class SearchProviderSet {
  const SearchProviderSet({required this.providers, required this.statuses});
  final List<SearchProvider> providers;
  final List<SearchSourceStatus> statuses;
}

const List<String> kDefaultSearchOrder = <String>[
  'tavily', 'exa', 'brave', 'duckduckgo',
];

/// 按 order 构造可用 provider；缺 Key 的跳过并记入 statuses；未知名字跳过并记入。
SearchProviderSet buildSearchProviders({
  required List<String> order,
  required Credentials credentials,
  http.Client? client,
});

SearchService provideSearch(
  Context ctx, {
  List<String> order = kDefaultSearchOrder,
  Credentials? credentials,          // 缺省取 ctx 已提供的 'credentials' 服务
  List<SearchProvider>? providers,   // 显式覆盖，保留现有逃生口
  SearchService? search,
  http.Client? client,
});
```

**Key 解析顺序**：显式 `credentials` 参数 → `ctx.get<Credentials>('credentials')`
→ 都没有则只启用免 Key 的 DuckDuckGo。**不直接读环境变量**。

**`providers` 与 `order` 的关系**：传了显式 `providers` 时忽略 `order`，直接注册
这些实例（沿用现有逃生口语义）；该路径下 `statuses` 为空列表，因为没有经过
Key 检查。

**`SearchService` 增加装配期状态**：

```dart
class SearchService {
  SearchService({List<SearchSourceStatus> statuses = const <SearchSourceStatus>[]});
  List<SearchSourceStatus> get statuses;   // 装配快照，供失败文案与后续 /websearch-order 展示
}
```

`register` / `get` / `providers` / `search` 的语义不变；`statuses` 只在
`provideSearch` 装配时填充，动态 `register` 不改变它。

### 各 provider 契约

| | Tavily | Brave |
|---|---|---|
| 端点 | `POST https://api.tavily.com/search` | `GET https://api.search.brave.com/res/v1/web/search` |
| 鉴权 | `Authorization: Bearer <apiKey>` | `X-Subscription-Token: <apiKey>`、`Accept: application/json` |
| 请求 | `{query, max_results: limit, search_depth: 'basic'}` | `?q=<query>&count=<limit>` |
| 结果映射 | `results[]` → `title` / `url` / `content` | `web.results[]` → `title` / `url` / `description` |
| 无结果 | `results` 缺失 → 空列表 | `web` 缺失 → 空列表 |

两者都：非 200 抛 `SearchException('<name> HTTP <code>')`；JSON 非对象抛
`SearchException('<name> 返回了非对象 JSON')`；响应体解析异常不吞。

Exa 保持现有契约（`POST https://api.exa.ai/search`、`x-api-key`、
`{query, numResults, contents:{text:{maxCharacters:500}}}`），仅补上 `timeout`。

### 抓取接缝

```dart
enum FetchedFormat { text, markdown }

class FetchedPage {
  const FetchedPage({required this.url, required this.content, required this.format});
  final String url;
  final String content;
  final FetchedFormat format;
}

abstract class WebFetcher {
  Future<FetchedPage> fetch(String url, {int maxChars = 20000});
}

/// 默认实现：GET + stripHtml，等价于现有 FetchUrlTool 的行为。
class HttpFetcher implements WebFetcher {
  HttpFetcher({http.Client? client, Duration timeout = const Duration(seconds: 30)});
}

/// Firecrawl：POST https://api.firecrawl.dev/v1/scrape
/// 请求 {url, formats: ['markdown']}，取 data.markdown；success: false 视为失败。
class FirecrawlFetcher implements WebFetcher {
  FirecrawlFetcher({
    required String apiKey,
    String baseUrl = 'https://api.firecrawl.dev',
    http.Client? client,
    Duration timeout = const Duration(seconds: 60),
  });
}
```

`provideWebTools` 改为：

```dart
List<Tool> provideWebTools(
  Context ctx, {
  SearchService? search,       // 缺省 ctx.search
  WebFetcher? fetcher,         // 显式覆盖
  Credentials? credentials,    // 缺省 ctx 的 'credentials' 服务
  http.Client? client,
});
```

选后端：显式 `fetcher` → 有 `FIRECRAWL_API_KEY` 则 `FirecrawlFetcher` → 否则
`HttpFetcher`。

## 数据流

```
模型调用 web_search(query)
  → WebSearchTool.call
      → SearchService.search(query, limit)
          → 按注册顺序逐个 provider.search()，抛错则试下一个
          → 全部抛错 → 抛 SearchException(聚合原因)
      → 成功：格式化为编号列表 + value 里的 JSON 结果数组
      → 失败：ToolResult.failure(SEARCH_UNAVAILABLE, 明确文案)

模型调用 fetch_url(url)
  → FetchUrlTool.call
      → 校验 scheme（非 http/https → INVALID_URL）
      → WebFetcher.fetch(url, maxChars)
          → HttpFetcher：GET + stripHtml + 截断
          → FirecrawlFetcher：POST /v1/scrape → data.markdown + 截断
      → 失败：ToolResult.failure(FETCH_FAILED, 含「无法联网」前缀与原因)
```

## 错误处理与失败语义

**回退条件**：只有 provider 抛 `SearchException`（或其它异常）才试下一个；返回空
列表视为成功并直接返回。

**工具层文案**（fail-closed）：

```
无法联网：所有搜索源都不可用。
tavily: HTTP 401; brave: 连接超时
未配置的搜索源：exa（设置 EXA_API_KEY 后重试）
```

- 第一行固定前缀，让模型明确知道是「没有联网能力」而非「没有结果」。
- 第二行是 `SearchException.message` 的聚合原因（沿用现有格式）。
- 第三行由 `SearchService.statuses` 里 `available == false` 的源生成，缺失时省略。
- `error.code` 为 `SEARCH_UNAVAILABLE`。

`fetch_url` 同口径：文案带「无法联网」前缀与底层原因，`error.code` 保持
`FETCH_FAILED`。

**超时**：每个 provider 默认 15s，`HttpFetcher` 30s，`FirecrawlFetcher` 60s。
这是新增能力——现状 provider 无超时，只靠 `conatus_code` 装配的 30s 工具超时兜底。

## 破坏性变更与适配

| 变更 | 影响 |
|---|---|
| `provideSearch` 移除 `exaApiKey`，新增 `order` / `credentials` | 包内 API 破坏性变更（0.x 版本可接受） |
| `provideWebTools` 新增 `fetcher` / `credentials` | 纯增量，向后兼容 |
| `SearchService` 构造函数新增可选 `statuses` | 纯增量 |
| `stripHtml` 从 `web_tools.dart` 迁到 `fetch/http_fetcher.dart` | barrel 导出路径调整，符号名不变 |
| `pubspec.yaml` 新增 `conatus_credentials` | 新依赖 |

需要跟着改的调用点（仅签名适配）：

- `packages/conatus_code/lib/src/tui/tui_app.dart:165` — `provideSearch(app, ...)`
- `example/voice_plan_mode.dart:77` — 同上

## 测试计划

| 文件 | 覆盖 |
|---|---|
| `test/search_tavily_test.dart` | 请求体（`max_results` / `search_depth`）、`Authorization` 头、`results[].content` 映射、401 抛错 |
| `test/search_brave_test.dart` | GET 查询参数、`X-Subscription-Token` 头、`web.results[].description` 映射、`web` 缺失返回空列表 |
| `test/search_registry_test.dart` | `order` 构造顺序、缺 Key 跳过且 `statuses.reason` 正确、未知名字跳过、显式 `providers` 覆盖、`kDefaultSearchOrder` 内容 |
| `test/fetch_http_test.dart` | 现有 `fetch_url` 行为迁入后不回退（去标签、实体、截断、`INVALID_URL`、非 200） |
| `test/fetch_firecrawl_test.dart` | 请求体 `formats:['markdown']`、`data.markdown` 解析、`success:false` 失败、鉴权头 |
| `test/web_tools_test.dart`（扩充） | `SEARCH_UNAVAILABLE` 文案含原因与「未配置的搜索源」、`fetcher` 注入生效、`provideWebTools` 自动选 Firecrawl |
| `test/search_test.dart`（更新） | 新 `provideSearch` 签名下的默认装配、`credentials` 从上下文回退、`statuses` 填充 |

既有测试的语义断言（顺序回退、显式 `provider:` 路由、空结果不触发回退）保持不变。

## 后续 spec（本设计之外）

1. **conatus_llm 服务端内置搜索**：工具原样透传通道 + `server_tool_use` /
   `web_search_tool_result` / `url_citation` 解析 + `LlmResult` / `LlmStreamEvent`
   的 citations 承载 + 「是否真的执行了搜索」判定。这是「内置优先、静默忽略则降级」
   的前提。
2. **conatus_code 接线**：`[websearch]` 配置段（`order` 等）、`/websearch-auth`
   （录入 Key）、`/websearch-order`（调整顺序）、沙箱说明。
