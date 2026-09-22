# conatus_search 多 provider 搜索路由 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 `conatus_search` 加 Tavily / Brave 两个 HTTP 搜索源，把凭据统一到 `conatus_credentials`，按名字列表装配 provider 顺序，Firecrawl 作为 `fetch_url` 的可选抓取后端，并让搜索全失败时给出明确的「无法联网」文案。

**Architecture:** 沿用现有 `SearchProvider` / `SearchService` 接缝（顺序回退语义不变），新增一层「名字 → 工厂」的装配表 `search_registry.dart`，provider 各自实现一次查询；抓取侧新增 `WebFetcher` 接缝，默认 `HttpFetcher`（现有 stripHtml 逻辑迁入），配了 Firecrawl Key 时换 `FirecrawlFetcher`。

**Tech Stack:** Dart 3.6+、`http`、`conatus_core`（Context/Disposer）、`conatus_foundation`（Tool/ToolRegistry）、`conatus_credentials`（Credentials）、`package:test` + `package:http/testing`（MockClient）。

**Spec:** `docs/superpowers/specs/2026-09-22-conatus-search-provider-routing-design.md`

**工作目录：** 所有 `dart test` / `git` 命令默认在仓库根 `/Users/fitz/REPO/conatus` 下执行；测试命令用 `dart test packages/conatus_search/test/<file>`，或先 `cd packages/conatus_search` 再用相对路径。

---

## 文件结构

| 文件 | 职责 |
|---|---|
| `packages/conatus_search/pubspec.yaml` | 新增 `conatus_credentials` 依赖 |
| `packages/conatus_search/lib/src/search_http.dart` | **新增** provider 共用的超时归一化 |
| `packages/conatus_search/lib/src/search_types.dart` | 不变 |
| `packages/conatus_search/lib/src/search_tavily.dart` | **新增** TavilySearchProvider + `kTavilyCredentialKey` |
| `packages/conatus_search/lib/src/search_brave.dart` | **新增** BraveSearchProvider + `kBraveCredentialKey` |
| `packages/conatus_search/lib/src/search_exa.dart` | 加 `timeout` + `kExaCredentialKey` |
| `packages/conatus_search/lib/src/search_duckduckgo.dart` | 不变 |
| `packages/conatus_search/lib/src/search_registry.dart` | **新增** 装配表与 `buildSearchProviders` |
| `packages/conatus_search/lib/src/search.dart` | `SearchService.statuses` + `provideSearch` 改造 |
| `packages/conatus_search/lib/src/fetch/fetcher.dart` | **新增** `WebFetcher` / `FetchedPage` / `FetchException` |
| `packages/conatus_search/lib/src/fetch/http_fetcher.dart` | **新增** 默认抓取实现 + `stripHtml`（从 web_tools 迁入） |
| `packages/conatus_search/lib/src/fetch/firecrawl_fetcher.dart` | **新增** Firecrawl 抓取 + `kFirecrawlCredentialKey` |
| `packages/conatus_search/lib/src/web_tools.dart` | `FetchUrlTool` 走 `WebFetcher`；`WebSearchTool` fail-closed；`provideWebTools` 选后端 |
| `packages/conatus_search/lib/conatus_search.dart` | barrel 导出扩充 |
| `packages/conatus_code/lib/src/tui/tui_app.dart` | 调用点适配（删 `exaApiKey`，凭据块前移） |
| `packages/conatus_code/bin/conatus_code.dart` | 删 `exaApiKey:` 实参 |
| `packages/conatus_search/README.md` / `CHANGELOG.md` | 文档 |
| 根 `README.md` / `CHANGELOG.md` | 文档 |

---

## 前置约定

- `InMemoryCredentials` 的构造是 `InMemoryCredentials({Map<String, String> initial = const <String, String>{}})`（见 `conatus_credentials`）。计划里的 `InMemoryCredentials()` 表示空凭据；若本仓库实际签名要求显式传 `initial`，改写为 `InMemoryCredentials(initial: <String, String>{})` 即可，语义相同。
- 所有测试用 `MockClient`（`package:http/testing`）注入 HTTP 层，不发真实网络请求。
- 每个任务末尾提交一次，保持历史可回滚；单文件用 `dart test <path>`，整包用 `dart test packages/conatus_search`。
- 当前仓库未强制 `dart format`（既有文件同样不符合当前格式化器），因此**不要**跑 `dart format` 重排文件；风格对齐周围代码即可。

---

## Task 1: 加 conatus_credentials 依赖

**Files:**
- Modify: `packages/conatus_search/pubspec.yaml`

- [ ] **Step 1: 加依赖**

`dependencies` 段（保持字母序，`sort_pub_dependencies` lint 会检查）：

```yaml
dependencies:
  conatus_core: ^0.16.0
  conatus_credentials: ^0.16.0
  conatus_foundation: ^0.16.0
  http: ^1.2.0
```

- [ ] **Step 2: 解析依赖**

Run: `cd /Users/fitz/REPO/conatus && dart pub get`
Expected: `Got dependencies!`（workspace 内解析到本地 `packages/conatus_credentials`）

- [ ] **Step 3: 提交**

```bash
git add packages/conatus_search/pubspec.yaml pubspec.lock
git commit -m "build(search): 新增 conatus_credentials 依赖"
```

---

## Task 2: 超时归一化 helper + Exa 接入

**Files:**
- Create: `packages/conatus_search/lib/src/search_http.dart`
- Modify: `packages/conatus_search/lib/src/search_exa.dart`
- Test: `packages/conatus_search/test/search_http_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `packages/conatus_search/test/search_http_test.dart`：

```dart
import 'dart:async';
import 'package:conatus_search/conatus_search.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test('超时转成 SearchException，文案含 provider 名与秒数', () async {
    final Future<http.Response> slow = Future<http.Response>.delayed(
      const Duration(milliseconds: 100),
      () => http.Response('{}', 200),
    );

    await expectLater(
      sendWithTimeout(slow,
          timeout: const Duration(milliseconds: 10), provider: 'tavily'),
      throwsA(isA<SearchException>().having(
        (SearchException e) => e.message,
        'message',
        contains('tavily 请求超时'),
      )),
    );
  });

  test('未超时时原样返回响应', () async {
    final http.Response response = await sendWithTimeout(
      Future<http.Response>.value(http.Response('ok', 200)),
      timeout: const Duration(seconds: 5),
      provider: 'brave',
    );

    expect(response.statusCode, 200);
    expect(response.body, 'ok');
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/fitz/REPO/conatus && dart test packages/conatus_search/test/search_http_test.dart`
Expected: 编译失败 —— `sendWithTimeout` 未定义 / 未导出

- [ ] **Step 3: 实现 helper**

创建 `packages/conatus_search/lib/src/search_http.dart`：

```dart
/// provider 共用的 HTTP 细节：把请求超时归一成 [SearchException]。
library;

import 'dart:async';
import 'package:http/http.dart' as http;
import 'search_types.dart';

/// 等待 [future]，超过 [timeout] 抛 [SearchException]。
///
/// 各 provider 的 HTTP 客户端不直接暴露超时，统一在这里转换，使
/// `SearchService` 的聚合错误文案保持一致的形状（`'<provider>: <原因>'`）。
Future<http.Response> sendWithTimeout(
  Future<http.Response> future, {
  required Duration timeout,
  required String provider,
}) async {
  try {
    return await future.timeout(timeout);
  } on TimeoutException {
    throw SearchException('$provider 请求超时（${timeout.inSeconds}s）');
  }
}
```

- [ ] **Step 4: 临时导出以便测试**

`packages/conatus_search/lib/conatus_search.dart` 追加一行（Task 11 会重排整个 barrel，这里先让它可测）：

```dart
export 'src/search_http.dart' show sendWithTimeout;
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd /Users/fitz/REPO/conatus && dart test packages/conatus_search/test/search_http_test.dart`
Expected: `All tests passed!`（2 个用例）

- [ ] **Step 6: Exa 接入 timeout 与凭据键常量**

`packages/conatus_search/lib/src/search_exa.dart` 改为（新增 `timeout` 字段与 `kExaCredentialKey`，请求套 `sendWithTimeout`）：

```dart
/// Exa 搜索 provider（需 API Key）：调用 Exa 的 REST 搜索接口。
///
/// 仅在有 Key 时装配；`buildSearchProviders` 按 [kDefaultSearchOrder] 决定它排
/// 在哪个位置。
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'search_http.dart';
import 'search_types.dart';

/// Exa API Key 的凭据键名。
const String kExaCredentialKey = 'EXA_API_KEY';

/// Exa provider。
class ExaSearchProvider implements SearchProvider {
  ExaSearchProvider({
    required this.apiKey,
    http.Client? client,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 15),
  })  : _client = client ?? http.Client(),
        _endpoint = endpoint ?? Uri.parse('https://api.exa.ai/search');

  /// Exa API Key。
  final String apiKey;

  /// 单次查询超时。
  final Duration timeout;

  final http.Client _client;
  final Uri _endpoint;

  @override
  String get name => 'exa';

  @override
  Future<List<SearchResult>> search(String query, {int limit = 5}) async {
    final http.Response response = await sendWithTimeout(
      _client.post(
        _endpoint,
        headers: <String, String>{
          'content-type': 'application/json',
          'x-api-key': apiKey,
        },
        body: jsonEncode(<String, Object?>{
          'query': query,
          'numResults': limit,
          'contents': <String, Object?>{
            'text': <String, Object?>{'maxCharacters': 500},
          },
        }),
      ),
      timeout: timeout,
      provider: name,
    );
    if (response.statusCode != 200) {
      throw SearchException('exa HTTP ${response.statusCode}');
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const SearchException('exa 返回了非对象 JSON');
    }
    final List<Object?> raw =
        (decoded['results'] as List<Object?>?) ?? const <Object?>[];
    return <SearchResult>[
      for (final Object? item in raw)
        if (item is Map<String, Object?>) _toResult(item),
    ];
  }

  SearchResult _toResult(Map<String, Object?> item) => SearchResult(
        title: item['title'] as String? ?? '',
        url: item['url'] as String? ?? '',
        snippet:
            (item['text'] as String?) ?? (item['summary'] as String?) ?? '',
      );
}
```

- [ ] **Step 7: 跑 Exa 既有测试确认没回归**

Run: `cd /Users/fitz/REPO/conatus && dart test packages/conatus_search/test/search_exa_test.dart`
Expected: `All tests passed!`（2 个用例，行为不变）

- [ ] **Step 8: 提交**

```bash
git add packages/conatus_search/lib/src/search_http.dart \
        packages/conatus_search/lib/src/search_exa.dart \
        packages/conatus_search/lib/conatus_search.dart \
        packages/conatus_search/test/search_http_test.dart
git commit -m "feat(search): 新增超时归一化 helper，Exa 接入 timeout 与凭据键常量"
```

---

## Task 3: TavilySearchProvider

**Files:**
- Create: `packages/conatus_search/lib/src/search_tavily.dart`
- Test: `packages/conatus_search/test/search_tavily_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `packages/conatus_search/test/search_tavily_test.dart`：

```dart
import 'dart:convert';
import 'package:conatus_search/conatus_search.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('解析 results[].content，携带 Bearer 与 max_results', () async {
    http.Request? captured;
    final TavilySearchProvider provider = TavilySearchProvider(
      apiKey: 'tvly-secret',
      client: MockClient((http.Request request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'results': <Object?>[
              <String, Object?>{
                'title': 'T',
                'url': 'https://t.com',
                'content': 'C',
              },
              <String, Object?>{'title': 'T2', 'url': 'https://t2.com'},
            ],
          }),
          200,
        );
      }),
    );

    final List<SearchResult> results = await provider.search('query', limit: 3);

    expect(provider.name, 'tavily');
    expect(results, hasLength(2));
    expect(results.first.title, 'T');
    expect(results.first.url, 'https://t.com');
    expect(results.first.snippet, 'C');
    expect(captured!.headers['authorization'], 'Bearer tvly-secret');
    expect(captured!.url.path, '/search');
    final Map<String, Object?> body =
        jsonDecode(captured!.body) as Map<String, Object?>;
    expect(body['query'], 'query');
    expect(body['max_results'], 3);
    expect(body['search_depth'], 'basic');
  });

  test('limit 超过 20 时钳到 20', () async {
    http.Request? captured;
    final TavilySearchProvider provider = TavilySearchProvider(
      apiKey: 'k',
      client: MockClient((http.Request request) async {
        captured = request;
        return http.Response('{"results": []}', 200);
      }),
    );

    await provider.search('q', limit: 100);

    final Map<String, Object?> body =
        jsonDecode(captured!.body) as Map<String, Object?>;
    expect(body['max_results'], 20);
  });

  test('results 缺失返回空列表', () async {
    final TavilySearchProvider provider = TavilySearchProvider(
      apiKey: 'k',
      client: MockClient(
          (http.Request request) async => http.Response('{"query": "q"}', 200)),
    );

    expect(await provider.search('q'), isEmpty);
  });

  test('非 200 抛 SearchException', () async {
    final TavilySearchProvider provider = TavilySearchProvider(
      apiKey: 'k',
      client: MockClient(
          (http.Request request) async => http.Response('{}', 401)),
    );

    await expectLater(
      provider.search('q'),
      throwsA(isA<SearchException>().having(
        (SearchException e) => e.message,
        'message',
        'tavily HTTP 401',
      )),
    );
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/fitz/REPO/conatus && dart test packages/conatus_search/test/search_tavily_test.dart`
Expected: 编译失败 —— `TavilySearchProvider` 未定义

- [ ] **Step 3: 实现 provider**

创建 `packages/conatus_search/lib/src/search_tavily.dart`：

```dart
/// Tavily 搜索 provider（需 API Key）：面向 LLM 的搜索接口。
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'search_http.dart';
import 'search_types.dart';

/// Tavily API Key 的凭据键名。
const String kTavilyCredentialKey = 'TAVILY_API_KEY';

/// Tavily 单次查询的结果数上限（上游限制）。
const int kTavilyMaxResults = 20;

/// Tavily provider。
class TavilySearchProvider implements SearchProvider {
  TavilySearchProvider({
    required this.apiKey,
    http.Client? client,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 15),
  })  : _client = client ?? http.Client(),
        _endpoint = endpoint ?? Uri.parse('https://api.tavily.com/search');

  /// Tavily API Key。
  final String apiKey;

  /// 单次查询超时。
  final Duration timeout;

  final http.Client _client;
  final Uri _endpoint;

  @override
  String get name => 'tavily';

  @override
  Future<List<SearchResult>> search(String query, {int limit = 5}) async {
    final http.Response response = await sendWithTimeout(
      _client.post(
        _endpoint,
        headers: <String, String>{
          'content-type': 'application/json',
          'authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(<String, Object?>{
          'query': query,
          'max_results': limit.clamp(1, kTavilyMaxResults),
          'search_depth': 'basic',
        }),
      ),
      timeout: timeout,
      provider: name,
    );
    if (response.statusCode != 200) {
      throw SearchException('tavily HTTP ${response.statusCode}');
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const SearchException('tavily 返回了非对象 JSON');
    }
    final List<Object?> raw =
        (decoded['results'] as List<Object?>?) ?? const <Object?>[];
    return <SearchResult>[
      for (final Object? item in raw)
        if (item is Map<String, Object?>)
          SearchResult(
            title: item['title'] as String? ?? '',
            url: item['url'] as String? ?? '',
            snippet: item['content'] as String? ?? '',
          ),
    ];
  }
}
```

- [ ] **Step 4: 临时导出**

`packages/conatus_search/lib/conatus_search.dart` 追加：

```dart
export 'src/search_tavily.dart' show TavilySearchProvider, kTavilyCredentialKey;
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd /Users/fitz/REPO/conatus && dart test packages/conatus_search/test/search_tavily_test.dart`
Expected: `All tests passed!`（4 个用例）

- [ ] **Step 6: 提交**

```bash
git add packages/conatus_search/lib/src/search_tavily.dart \
        packages/conatus_search/lib/conatus_search.dart \
        packages/conatus_search/test/search_tavily_test.dart
git commit -m "feat(search): 新增 Tavily 搜索 provider"
```

---

## Task 4: BraveSearchProvider

**Files:**
- Create: `packages/conatus_search/lib/src/search_brave.dart`
- Test: `packages/conatus_search/test/search_brave_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `packages/conatus_search/test/search_brave_test.dart`：

```dart
import 'dart:convert';
import 'package:conatus_search/conatus_search.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('解析 web.results[].description，携带 X-Subscription-Token 与查询参数',
      () async {
    http.Request? captured;
    final BraveSearchProvider provider = BraveSearchProvider(
      apiKey: 'brave-secret',
      client: MockClient((http.Request request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'web': <String, Object?>{
              'results': <Object?>[
                <String, Object?>{
                  'title': 'T',
                  'url': 'https://b.com',
                  'description': 'D',
                },
              ],
            },
          }),
          200,
        );
      }),
    );

    final List<SearchResult> results = await provider.search('天气', limit: 3);

    expect(provider.name, 'brave');
    expect(results.single.title, 'T');
    expect(results.single.url, 'https://b.com');
    expect(results.single.snippet, 'D');
    expect(captured!.headers['x-subscription-token'], 'brave-secret');
    expect(captured!.url.path, '/res/v1/web/search');
    expect(captured!.url.queryParameters['q'], '天气');
    expect(captured!.url.queryParameters['count'], '3');
  });

  test('web 缺失返回空列表', () async {
    final BraveSearchProvider provider = BraveSearchProvider(
      apiKey: 'k',
      client: MockClient(
          (http.Request request) async => http.Response('{"type": "search"}', 200)),
    );

    expect(await provider.search('q'), isEmpty);
  });

  test('count 超过 20 时钳到 20', () async {
    http.Request? captured;
    final BraveSearchProvider provider = BraveSearchProvider(
      apiKey: 'k',
      client: MockClient((http.Request request) async {
        captured = request;
        return http.Response('{"web": {"results": []}}', 200);
      }),
    );

    await provider.search('q', limit: 100);

    expect(captured!.url.queryParameters['count'], '20');
  });

  test('非 200 抛 SearchException', () async {
    final BraveSearchProvider provider = BraveSearchProvider(
      apiKey: 'k',
      client: MockClient(
          (http.Request request) async => http.Response('{}', 429)),
    );

    await expectLater(
      provider.search('q'),
      throwsA(isA<SearchException>().having(
        (SearchException e) => e.message,
        'message',
        'brave HTTP 429',
      )),
    );
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/fitz/REPO/conatus && dart test packages/conatus_search/test/search_brave_test.dart`
Expected: 编译失败 —— `BraveSearchProvider` 未定义

- [ ] **Step 3: 实现 provider**

创建 `packages/conatus_search/lib/src/search_brave.dart`：

```dart
/// Brave Search provider（需 API Key）：调用 Brave 的 web search 接口。
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'search_http.dart';
import 'search_types.dart';

/// Brave Search API Key 的凭据键名。
const String kBraveCredentialKey = 'BRAVE_API_KEY';

/// Brave 单次查询的结果数上限（上游限制）。
const int kBraveMaxCount = 20;

/// Brave provider。
class BraveSearchProvider implements SearchProvider {
  BraveSearchProvider({
    required this.apiKey,
    http.Client? client,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 15),
  })  : _client = client ?? http.Client(),
        _endpoint = endpoint ??
            Uri.parse('https://api.search.brave.com/res/v1/web/search');

  /// Brave Search API Key。
  final String apiKey;

  /// 单次查询超时。
  final Duration timeout;

  final http.Client _client;
  final Uri _endpoint;

  @override
  String get name => 'brave';

  @override
  Future<List<SearchResult>> search(String query, {int limit = 5}) async {
    final Uri uri = _endpoint.replace(queryParameters: <String, String>{
      'q': query,
      'count': '${limit.clamp(1, kBraveMaxCount)}',
    });
    final http.Response response = await sendWithTimeout(
      _client.get(
        uri,
        headers: <String, String>{
          'accept': 'application/json',
          'x-subscription-token': apiKey,
        },
      ),
      timeout: timeout,
      provider: name,
    );
    if (response.statusCode != 200) {
      throw SearchException('brave HTTP ${response.statusCode}');
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const SearchException('brave 返回了非对象 JSON');
    }
    final Object? web = decoded['web'];
    if (web is! Map<String, Object?>) {
      return const <SearchResult>[];
    }
    final List<Object?> raw =
        (web['results'] as List<Object?>?) ?? const <Object?>[];
    return <SearchResult>[
      for (final Object? item in raw)
        if (item is Map<String, Object?>)
          SearchResult(
            title: item['title'] as String? ?? '',
            url: item['url'] as String? ?? '',
            snippet: item['description'] as String? ?? '',
          ),
    ];
  }
}
```

- [ ] **Step 4: 临时导出**

`packages/conatus_search/lib/conatus_search.dart` 追加：

```dart
export 'src/search_brave.dart' show BraveSearchProvider, kBraveCredentialKey;
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd /Users/fitz/REPO/conatus && dart test packages/conatus_search/test/search_brave_test.dart`
Expected: `All tests passed!`（4 个用例）

- [ ] **Step 6: 提交**

```bash
git add packages/conatus_search/lib/src/search_brave.dart \
        packages/conatus_search/lib/conatus_search.dart \
        packages/conatus_search/test/search_brave_test.dart
git commit -m "feat(search): 新增 Brave 搜索 provider"
```

---

## Task 5: 装配表与 buildSearchProviders

**Files:**
- Create: `packages/conatus_search/lib/src/search_registry.dart`
- Test: `packages/conatus_search/test/search_registry_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `packages/conatus_search/test/search_registry_test.dart`：

```dart
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/fitz/REPO/conatus && dart test packages/conatus_search/test/search_registry_test.dart`
Expected: 编译失败 —— `buildSearchProviders` 未定义

- [ ] **Step 3: 实现装配表**

创建 `packages/conatus_search/lib/src/search_registry.dart`：

```dart
/// 搜索源装配：名字 → 工厂表，按顺序构造可用 provider。
library;

import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:http/http.dart' as http;
import 'search_brave.dart';
import 'search_duckduckgo.dart';
import 'search_exa.dart';
import 'search_tavily.dart';
import 'search_types.dart';

/// provider 构造所需的依赖。
class SearchProviderDeps {
  const SearchProviderDeps({
    required this.credentials,
    this.client,
    this.timeout = const Duration(seconds: 15),
  });

  /// 凭据来源（Key 的唯一来源）。
  final Credentials credentials;

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
  'duckduckgo': SearchProviderSpec(
    name: 'duckduckgo',
    credentialKey: '',
    create: _createDuckDuckGo,
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

SearchProvider _createDuckDuckGo(String apiKey, SearchProviderDeps deps) =>
    DuckDuckGoSearchProvider(client: deps.client);

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

  /// 与 [providers] 同序的状态列表（含被跳过的源）。
  final List<SearchSourceStatus> statuses;
}

/// 缺省搜索源顺序。
const List<String> kDefaultSearchOrder = <String>[
  'tavily',
  'exa',
  'brave',
  'duckduckgo',
];

/// 按 [order] 构造可用 provider；缺 Key 或名字未知的源跳过并记入 statuses。
SearchProviderSet buildSearchProviders({
  required List<String> order,
  required Credentials credentials,
  http.Client? client,
}) {
  final SearchProviderDeps deps =
      SearchProviderDeps(credentials: credentials, client: client);
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
    final Credential? credential = spec.credentialKey.isEmpty
        ? null
        : credentials.get(spec.credentialKey);
    if (spec.credentialKey.isNotEmpty && credential == null) {
      statuses.add(SearchSourceStatus(
        name: name,
        available: false,
        reason: '缺少 ${spec.credentialKey}',
      ));
      continue;
    }
    providers.add(spec.create(credential?.value ?? '', deps));
    statuses.add(SearchSourceStatus(name: name, available: true));
  }
  return SearchProviderSet(providers: providers, statuses: statuses);
}
```

- [ ] **Step 4: 临时导出**

`packages/conatus_search/lib/conatus_search.dart` 追加：

```dart
export 'src/search_registry.dart'
    show
        SearchProviderDeps,
        SearchProviderSet,
        SearchProviderSpec,
        SearchSourceStatus,
        buildSearchProviders,
        kDefaultSearchOrder,
        kSearchProviderSpecs;
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd /Users/fitz/REPO/conatus && dart test packages/conatus_search/test/search_registry_test.dart`
Expected: `All tests passed!`（6 个用例）

- [ ] **Step 6: 提交**

```bash
git add packages/conatus_search/lib/src/search_registry.dart \
        packages/conatus_search/lib/conatus_search.dart \
        packages/conatus_search/test/search_registry_test.dart
git commit -m "feat(search): 新增搜索源装配表与 buildSearchProviders"
```

---

## Task 6: SearchService.statuses + provideSearch 改造

**Files:**
- Modify: `packages/conatus_search/lib/src/search.dart`
- Test: `packages/conatus_search/test/search_test.dart`

- [ ] **Step 1: 更新测试（改成新签名）**

把 `packages/conatus_search/test/search_test.dart` 的 `provideSearch / ctx.search` 分组替换为：

```dart
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
```

同时在文件头部 import 区补上：

```dart
import 'package:conatus_credentials/conatus_credentials.dart';
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/fitz/REPO/conatus && dart test packages/conatus_search/test/search_test.dart`
Expected: 编译失败 —— `provideSearch` 没有 `credentials` / `order` 参数，`SearchService.statuses` 未定义

- [ ] **Step 3: 改造 search.dart**

`packages/conatus_search/lib/src/search.dart` 改为：

```dart
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
    return SearchProviderSet(
      providers: <SearchProvider>[DuckDuckGoSearchProvider(client: client)],
      statuses: <SearchSourceStatus>[
        for (final String name in order)
          SearchSourceStatus(
            name: name,
            available: name == 'duckduckgo',
            reason: name == 'duckduckgo' ? '' : '未提供凭据服务',
          ),
      ],
    );
  }
  return buildSearchProviders(
    order: order,
    credentials: resolved,
    client: client,
  );
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd /Users/fitz/REPO/conatus && dart test packages/conatus_search/test/search_test.dart`
Expected: `All tests passed!`（9 个用例：4 个 SearchService + 5 个 provideSearch）

- [ ] **Step 5: 跑整个包确认没别处回归**

Run: `cd /Users/fitz/REPO/conatus && dart test packages/conatus_search`
Expected: 全部通过（`web_tools_test.dart` 里 `provideSearch(ctx)` 的用法仍然合法）

- [ ] **Step 6: 提交**

```bash
git add packages/conatus_search/lib/src/search.dart \
        packages/conatus_search/test/search_test.dart
git commit -m "feat(search)!: provideSearch 改为按 order + Credentials 装配，SearchService 暴露 statuses"
```

---

## Task 7: WebFetcher 抽象 + HttpFetcher

**Files:**
- Create: `packages/conatus_search/lib/src/fetch/fetcher.dart`
- Create: `packages/conatus_search/lib/src/fetch/http_fetcher.dart`
- Test: `packages/conatus_search/test/fetch_http_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `packages/conatus_search/test/fetch_http_test.dart`：

```dart
import 'package:conatus_search/conatus_search.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('抓取并去标签，格式为 text', () async {
    final HttpFetcher fetcher = HttpFetcher(
      client: MockClient((http.Request request) async => http.Response(
            '<html><body><script>bad()</script><p>Hello &amp; world</p></body></html>',
            200,
          )),
    );

    final FetchedPage page = await fetcher.fetch('https://e.com');

    expect(page.content, 'Hello & world');
    expect(page.format, FetchedFormat.text);
    expect(page.url, 'https://e.com');
  });

  test('按 maxChars 截断', () async {
    final HttpFetcher fetcher = HttpFetcher(
      client: MockClient(
          (http.Request request) async => http.Response('<p>abcdefghij</p>', 200)),
    );

    final FetchedPage page = await fetcher.fetch('https://e.com', maxChars: 5);

    expect(page.content, 'abcde');
  });

  test('非 200 抛 FetchException', () async {
    final HttpFetcher fetcher = HttpFetcher(
      client: MockClient((http.Request request) async => http.Response('', 404)),
    );

    await expectLater(
      fetcher.fetch('https://e.com'),
      throwsA(isA<FetchException>().having(
        (FetchException e) => e.message,
        'message',
        'HTTP 404',
      )),
    );
  });

  test('超时抛 FetchException', () async {
    final HttpFetcher fetcher = HttpFetcher(
      timeout: const Duration(milliseconds: 10),
      client: MockClient((http.Request request) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return http.Response('ok', 200);
      }),
    );

    await expectLater(
      fetcher.fetch('https://e.com'),
      throwsA(isA<FetchException>()),
    );
  });

  test('stripHtml 去块、去标签、解码实体', () {
    expect(stripHtml('<style>x{}</style><div>a &lt;b&gt; c</div>'), 'a <b> c');
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/fitz/REPO/conatus && dart test packages/conatus_search/test/fetch_http_test.dart`
Expected: 编译失败 —— `HttpFetcher` / `FetchedPage` / `FetchedFormat` / `FetchException` 未定义

- [ ] **Step 3: 实现接缝**

创建 `packages/conatus_search/lib/src/fetch/fetcher.dart`：

```dart
/// 网页抓取接缝：把 URL 变成模型可读的正文。
library;

/// 抓取结果的正文形态。
enum FetchedFormat {
  /// 剥离标签后的纯文本。
  text,

  /// 已转换的 markdown。
  markdown,
}

/// 一次抓取的结果。
class FetchedPage {
  const FetchedPage({
    required this.url,
    required this.content,
    required this.format,
  });

  /// 抓取的 URL。
  final String url;

  /// 正文（已按 `maxChars` 截断）。
  final String content;

  /// 正文形态。
  final FetchedFormat format;
}

/// 抓取失败。
class FetchException implements Exception {
  const FetchException(this.message);

  /// 人可读的失败说明。
  final String message;

  @override
  String toString() => 'FetchException: $message';
}

/// 抓取接缝。
abstract class WebFetcher {
  /// 抓取 [url]，正文最多 [maxChars] 字符；失败抛 [FetchException]。
  Future<FetchedPage> fetch(String url, {int maxChars = 20000});
}
```

- [ ] **Step 4: 实现 HttpFetcher（stripHtml 迁入）**

创建 `packages/conatus_search/lib/src/fetch/http_fetcher.dart`：

```dart
/// 默认抓取实现：直接 GET 并剥离 HTML 标签。
library;

import 'dart:async';
import 'package:http/http.dart' as http;
import 'fetcher.dart';

/// 用 `http` 包直连的抓取器。
class HttpFetcher implements WebFetcher {
  HttpFetcher({
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// 单次请求超时。
  final Duration timeout;

  @override
  Future<FetchedPage> fetch(String url, {int maxChars = 20000}) async {
    final http.Response response;
    try {
      response = await _client.get(Uri.parse(url)).timeout(timeout);
    } on TimeoutException {
      throw FetchException('请求超时（${timeout.inSeconds}s）');
    }
    if (response.statusCode != 200) {
      throw FetchException('HTTP ${response.statusCode}');
    }
    final String text = stripHtml(response.body);
    return FetchedPage(
      url: url,
      content: text.length > maxChars ? text.substring(0, maxChars) : text,
      format: FetchedFormat.text,
    );
  }
}

/// 去除 script/style 与标签，解码常见实体并压缩空白。
String stripHtml(String html) {
  final String withoutBlocks = html
      .replaceAll(
          RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ');
  return withoutBlocks
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'[ \t\r\n]+'), ' ')
      .trim();
}
```

- [ ] **Step 5: 临时导出**

`packages/conatus_search/lib/conatus_search.dart` 追加：

```dart
export 'src/fetch/fetcher.dart'
    show FetchedFormat, FetchedPage, FetchException, WebFetcher;
export 'src/fetch/http_fetcher.dart' show HttpFetcher, stripHtml;
```

**注意**：此刻 `src/web_tools.dart` 里还有一份 `stripHtml`，barrel 会重复导出同名符号。因此**同一步**里删掉 `web_tools.dart` 中的 `stripHtml` 函数定义，并把 `FetchUrlTool` 的 `import 'search.dart';` 段落下方加上：

```dart
import 'fetch/http_fetcher.dart';
```

（`FetchUrlTool` 此时仍用旧的裸 http 实现，只是 `stripHtml` 改从新文件引入；Task 9 再把它换成 `WebFetcher`。）

- [ ] **Step 6: 跑测试确认通过**

Run: `cd /Users/fitz/REPO/conatus && dart test packages/conatus_search/test/fetch_http_test.dart packages/conatus_search/test/web_tools_test.dart`
Expected: 两个文件全部通过（`web_tools_test.dart` 的 `stripHtml` 用例改指新实现，行为不变）

- [ ] **Step 7: 提交**

```bash
git add packages/conatus_search/lib/src/fetch \
        packages/conatus_search/lib/src/web_tools.dart \
        packages/conatus_search/lib/conatus_search.dart \
        packages/conatus_search/test/fetch_http_test.dart
git commit -m "feat(search): 新增 WebFetcher 接缝与 HttpFetcher，stripHtml 迁入"
```

---

## Task 8: FirecrawlFetcher

**Files:**
- Create: `packages/conatus_search/lib/src/fetch/firecrawl_fetcher.dart`
- Test: `packages/conatus_search/test/fetch_firecrawl_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `packages/conatus_search/test/fetch_firecrawl_test.dart`：

```dart
import 'dart:convert';
import 'package:conatus_search/conatus_search.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('POST /v1/scrape，解析 data.markdown，格式为 markdown', () async {
    http.Request? captured;
    final FirecrawlFetcher fetcher = FirecrawlFetcher(
      apiKey: 'fc-secret',
      client: MockClient((http.Request request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'success': true,
            'data': <String, Object?>{'markdown': '# 标题\n正文'},
          }),
          200,
        );
      }),
    );

    final FetchedPage page = await fetcher.fetch('https://e.com');

    expect(page.content, '# 标题\n正文');
    expect(page.format, FetchedFormat.markdown);
    expect(captured!.url.path, '/v1/scrape');
    expect(captured!.headers['authorization'], 'Bearer fc-secret');
    final Map<String, Object?> body =
        jsonDecode(captured!.body) as Map<String, Object?>;
    expect(body['url'], 'https://e.com');
    expect(body['formats'], <String>['markdown']);
  });

  test('按 maxChars 截断 markdown', () async {
    final FirecrawlFetcher fetcher = FirecrawlFetcher(
      apiKey: 'k',
      client: MockClient((http.Request request) async => http.Response(
            '{"success": true, "data": {"markdown": "abcdefghij"}}',
            200,
          )),
    );

    final FetchedPage page = await fetcher.fetch('https://e.com', maxChars: 4);

    expect(page.content, 'abcd');
  });

  test('success:false 抛 FetchException 并带上原因', () async {
    final FirecrawlFetcher fetcher = FirecrawlFetcher(
      apiKey: 'k',
      client: MockClient((http.Request request) async => http.Response(
            '{"success": false, "error": "Blocked"}',
            200,
          )),
    );

    await expectLater(
      fetcher.fetch('https://e.com'),
      throwsA(isA<FetchException>().having(
        (FetchException e) => e.message,
        'message',
        contains('Blocked'),
      )),
    );
  });

  test('非 200 抛 FetchException', () async {
    final FirecrawlFetcher fetcher = FirecrawlFetcher(
      apiKey: 'k',
      client: MockClient(
          (http.Request request) async => http.Response('{}', 402)),
    );

    await expectLater(
      fetcher.fetch('https://e.com'),
      throwsA(isA<FetchException>().having(
        (FetchException e) => e.message,
        'message',
        'Firecrawl HTTP 402',
      )),
    );
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/fitz/REPO/conatus && dart test packages/conatus_search/test/fetch_firecrawl_test.dart`
Expected: 编译失败 —— `FirecrawlFetcher` 未定义

- [ ] **Step 3: 实现 FirecrawlFetcher**

创建 `packages/conatus_search/lib/src/fetch/firecrawl_fetcher.dart`：

```dart
/// Firecrawl 抓取后端：把网页转成 markdown（含 JS 渲染与反爬处理）。
library;

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'fetcher.dart';

/// Firecrawl API Key 的凭据键名。
const String kFirecrawlCredentialKey = 'FIRECRAWL_API_KEY';

/// 走 Firecrawl `/v1/scrape` 的抓取器。
class FirecrawlFetcher implements WebFetcher {
  FirecrawlFetcher({
    required this.apiKey,
    http.Client? client,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 60),
  })  : _client = client ?? http.Client(),
        _endpoint =
            endpoint ?? Uri.parse('https://api.firecrawl.dev/v1/scrape');

  /// Firecrawl API Key。
  final String apiKey;

  /// 单次请求超时。
  final Duration timeout;

  final http.Client _client;
  final Uri _endpoint;

  @override
  Future<FetchedPage> fetch(String url, {int maxChars = 20000}) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            _endpoint,
            headers: <String, String>{
              'content-type': 'application/json',
              'authorization': 'Bearer $apiKey',
            },
            body: jsonEncode(<String, Object?>{
              'url': url,
              'formats': <String>['markdown'],
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw FetchException('Firecrawl 请求超时（${timeout.inSeconds}s）');
    }
    if (response.statusCode != 200) {
      throw FetchException('Firecrawl HTTP ${response.statusCode}');
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FetchException('Firecrawl 返回了非对象 JSON');
    }
    if (decoded['success'] == false) {
      throw FetchException('Firecrawl 抓取失败：${decoded['error'] ?? '未知原因'}');
    }
    final Object? data = decoded['data'];
    if (data is! Map<String, Object?>) {
      throw const FetchException('Firecrawl 响应缺少 data');
    }
    final String markdown = data['markdown'] as String? ?? '';
    return FetchedPage(
      url: url,
      content: markdown.length > maxChars
          ? markdown.substring(0, maxChars)
          : markdown,
      format: FetchedFormat.markdown,
    );
  }
}
```

- [ ] **Step 4: 临时导出**

`packages/conatus_search/lib/conatus_search.dart` 追加：

```dart
export 'src/fetch/firecrawl_fetcher.dart'
    show FirecrawlFetcher, kFirecrawlCredentialKey;
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd /Users/fitz/REPO/conatus && dart test packages/conatus_search/test/fetch_firecrawl_test.dart`
Expected: `All tests passed!`（4 个用例）

- [ ] **Step 6: 提交**

```bash
git add packages/conatus_search/lib/src/fetch/firecrawl_fetcher.dart \
        packages/conatus_search/lib/conatus_search.dart \
        packages/conatus_search/test/fetch_firecrawl_test.dart
git commit -m "feat(search): 新增 Firecrawl 抓取后端"
```

---

## Task 9: FetchUrlTool 走 WebFetcher + provideWebTools 选后端

**Files:**
- Modify: `packages/conatus_search/lib/src/web_tools.dart`
- Test: `packages/conatus_search/test/web_tools_test.dart`

- [ ] **Step 1: 更新测试**

在 `packages/conatus_search/test/web_tools_test.dart` 的 `FetchUrlTool` 分组末尾追加：

```dart
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
```

并在文件顶部（`_StubProvider` 之后）加入两个测试替身：

```dart
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
```

把 `provideWebTools` 分组的用例替换为：

```dart
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
```

顶部 import 区补：

```dart
import 'package:conatus_credentials/conatus_credentials.dart';
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/fitz/REPO/conatus && dart test packages/conatus_search/test/web_tools_test.dart`
Expected: 编译失败 —— `FetchUrlTool.fetcher` 未定义，`provideWebTools` 没有 `credentials` 参数

- [ ] **Step 3: 改造 web_tools.dart**

`packages/conatus_search/lib/src/web_tools.dart` 改为（`FetchUrlTool` 换成 `WebFetcher`；`provideWebTools` 选后端；`stripHtml` 已迁走）：

```dart
/// web 工具：把搜索与抓取能力暴露给模型。
///
/// [WebSearchTool] 走 `ctx.search`（provider 回退由 SearchService 负责）；
/// [FetchUrlTool] 经 [WebFetcher] 抓取正文（缺省裸 http，配了 Firecrawl Key 时
/// 走 Firecrawl）。二者都是 [ToolRisk.low] 的只读工具，用 [provideWebTools]
/// 一次性注册到 `ctx.tools`。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:http/http.dart' as http;
import 'fetch/fetcher.dart';
import 'fetch/firecrawl_fetcher.dart';
import 'fetch/http_fetcher.dart';
import 'search.dart';

/// 联网搜索工具。
class WebSearchTool extends Tool {
  WebSearchTool({required SearchService search, this.defaultLimit = 5})
      : _search = search;

  final SearchService _search;

  /// 未显式传 `limit` 时的默认条数。
  final int defaultLimit;

  @override
  String get name => 'web_search';

  @override
  String get description => '在互联网上搜索，返回结果的标题、链接与摘要。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('query', required: true, description: '搜索关键词'),
        ParamSpec.integer('limit', description: '返回条数'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String query = ctx.str('query');
    final int limit = ctx.integer('limit') ?? defaultLimit;
    final List<SearchResult> results =
        await _search.search(query, limit: limit);
    if (results.isEmpty) {
      return ToolResult.success(
        '未找到与 "$query" 相关的结果',
        value: const <Object?>[],
      );
    }
    final StringBuffer buffer = StringBuffer('搜索 "$query" 的结果：');
    for (int i = 0; i < results.length; i++) {
      final SearchResult result = results[i];
      buffer
        ..write('\n${i + 1}. ${result.title}')
        ..write('\n   ${result.url}');
      if (result.snippet.isNotEmpty) buffer.write('\n   ${result.snippet}');
    }
    return ToolResult.success(
      buffer.toString(),
      value: <Map<String, Object?>>[
        for (final SearchResult result in results) result.toJson(),
      ],
    );
  }
}

/// 抓取网页并返回正文。
class FetchUrlTool extends Tool {
  FetchUrlTool({
    WebFetcher? fetcher,
    http.Client? client,
    this.maxChars = 20000,
  }) : _fetcher = fetcher ?? HttpFetcher(client: client);

  final WebFetcher _fetcher;

  /// 返回正文的最大字符数（超出截断）。
  final int maxChars;

  /// 当前使用的抓取后端（供测试与诊断）。
  WebFetcher get fetcher => _fetcher;

  @override
  String get name => 'fetch_url';

  @override
  String get description => '抓取一个网页并返回其正文内容。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('url', required: true, description: 'http(s) 链接'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String raw = ctx.str('url');
    final Uri? uri = Uri.tryParse(raw);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return ToolResult.failure(
        '仅支持 http/https 链接："$raw"',
        error: ToolError('INVALID_URL', 'unsupported url "$raw"'),
      );
    }
    final FetchedPage page;
    try {
      page = await _fetcher.fetch(raw, maxChars: maxChars);
    } on FetchException catch (error) {
      return ToolResult.failure(
        '无法联网：抓取 $raw 失败。${error.message}',
        error: ToolError('FETCH_FAILED', error.message),
      );
    }
    return ToolResult.success(
      page.content,
      value: <String, Object?>{'url': page.url, 'format': page.format.name},
    );
  }
}

/// 把 web 工具注册到 `ctx.tools`，返回已注册的工具。
///
/// [search] 缺省取上下文的 `'search'` 服务；[fetcher] 显式给出时优先，
/// 否则有 `FIRECRAWL_API_KEY` 时用 [FirecrawlFetcher]，都没有则 [HttpFetcher]。
List<Tool> provideWebTools(
  Context ctx, {
  SearchService? search,
  WebFetcher? fetcher,
  Credentials? credentials,
  http.Client? client,
}) {
  final SearchService service = search ?? ctx.search;
  final List<Tool> registered = <Tool>[
    WebSearchTool(search: service),
    FetchUrlTool(
      fetcher: fetcher ?? _resolveFetcher(ctx, credentials, client),
    ),
  ];
  for (final Tool tool in registered) {
    ctx.effect(() => ctx.tools.register(tool));
  }
  return registered;
}

WebFetcher _resolveFetcher(
  Context ctx,
  Credentials? credentials,
  http.Client? client,
) {
  final Credentials? resolved =
      credentials ?? ctx.get<Credentials>('credentials');
  final Credential? key = resolved?.get(kFirecrawlCredentialKey);
  if (key == null) return HttpFetcher(client: client);
  return FirecrawlFetcher(apiKey: key.value, client: client);
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd /Users/fitz/REPO/conatus && dart test packages/conatus_search/test/web_tools_test.dart`
Expected: `All tests passed!`（WebSearchTool 2 + FetchUrlTool 5 + stripHtml 1 + provideWebTools 3 = 11 个用例）

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_search/lib/src/web_tools.dart \
        packages/conatus_search/test/web_tools_test.dart
git commit -m "feat(search): FetchUrlTool 走 WebFetcher 接缝，provideWebTools 按 Key 选抓取后端"
```

---

## Task 10: WebSearchTool 的 fail-closed 文案

**Files:**
- Modify: `packages/conatus_search/lib/src/web_tools.dart`（`WebSearchTool.call`）
- Test: `packages/conatus_search/test/web_tools_test.dart`（`WebSearchTool` 分组）

- [ ] **Step 1: 写失败测试**

在 `packages/conatus_search/test/web_tools_test.dart` 的 `WebSearchTool` 分组末尾追加：

```dart
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
```

并在测试替身区加入：

```dart
class _FailingProvider implements SearchProvider {
  @override
  String get name => 'failing';

  @override
  Future<List<SearchResult>> search(String query, {int limit = 5}) async =>
      throw const SearchException('boom');
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/fitz/REPO/conatus && dart test packages/conatus_search/test/web_tools_test.dart`
Expected: 2 个新用例 FAIL —— 异常直接冒泡，`result.isError` 为 false、`result.error` 为 null

- [ ] **Step 3: 实现 fail-closed**

把 `packages/conatus_search/lib/src/web_tools.dart` 里 `WebSearchTool.call` 的开头：

```dart
  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String query = ctx.str('query');
    final int limit = ctx.integer('limit') ?? defaultLimit;
    final List<SearchResult> results =
        await _search.search(query, limit: limit);
    if (results.isEmpty) {
```

替换为：

```dart
  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String query = ctx.str('query');
    final int limit = ctx.integer('limit') ?? defaultLimit;
    final List<SearchResult> results;
    try {
      results = await _search.search(query, limit: limit);
    } on SearchException catch (error) {
      return ToolResult.failure(
        _unavailableMessage(error),
        error: ToolError('SEARCH_UNAVAILABLE', error.message),
      );
    }
    if (results.isEmpty) {
```

并在 `WebSearchTool` 类末尾（`call` 方法之后、类结束大括号之前）追加：

```dart
  /// 明确告知模型「没有联网能力」，并列出没配好的源。
  String _unavailableMessage(SearchException error) {
    final StringBuffer buffer = StringBuffer('无法联网：所有搜索源都不可用。\n')
      ..write(error.message);
    final List<SearchSourceStatus> skipped = <SearchSourceStatus>[
      for (final SearchSourceStatus status in _search.statuses)
        if (!status.available) status,
    ];
    if (skipped.isEmpty) return buffer.toString();
    buffer.write('\n未配置的搜索源：');
    buffer.write(skipped
        .map((SearchSourceStatus status) =>
            '${status.name}（${status.reason}）')
        .join('；'));
    return buffer.toString();
  }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd /Users/fitz/REPO/conatus && dart test packages/conatus_search/test/web_tools_test.dart`
Expected: `All tests passed!`（13 个用例）

- [ ] **Step 5: 跑整个包**

Run: `cd /Users/fitz/REPO/conatus && dart test packages/conatus_search`
Expected: 全部通过

- [ ] **Step 6: 提交**

```bash
git add packages/conatus_search/lib/src/web_tools.dart \
        packages/conatus_search/test/web_tools_test.dart
git commit -m "feat(search): web_search 全失败时返回 SEARCH_UNAVAILABLE 与明确文案"
```

---

## Task 11: barrel 导出重排

**Files:**
- Modify: `packages/conatus_search/lib/conatus_search.dart`

- [ ] **Step 1: 用最终版本整体替换 barrel**

`packages/conatus_search/lib/conatus_search.dart` 全量替换为（Task 2–8 里逐条追加的行在这里收敛成一份，导出按路径字母序，满足 `directives_ordering`）：

```dart
export 'src/fetch/fetcher.dart'
    show FetchedFormat, FetchedPage, FetchException, WebFetcher;
export 'src/fetch/firecrawl_fetcher.dart'
    show FirecrawlFetcher, kFirecrawlCredentialKey;
export 'src/fetch/http_fetcher.dart' show HttpFetcher, stripHtml;
export 'src/search.dart' show SearchContext, SearchService, provideSearch;
export 'src/search_brave.dart' show BraveSearchProvider, kBraveCredentialKey;
export 'src/search_duckduckgo.dart'
    show DuckDuckGoSearchProvider, parseDuckDuckGoHtml;
export 'src/search_exa.dart' show ExaSearchProvider, kExaCredentialKey;
export 'src/search_http.dart' show sendWithTimeout;
export 'src/search_registry.dart'
    show
        SearchProviderDeps,
        SearchProviderSet,
        SearchProviderSpec,
        SearchSourceStatus,
        buildSearchProviders,
        kDefaultSearchOrder,
        kSearchProviderSpecs;
export 'src/search_tavily.dart'
    show TavilySearchProvider, kTavilyCredentialKey;
export 'src/search_types.dart'
    show SearchException, SearchProvider, SearchResult;
export 'src/web_tools.dart' show FetchUrlTool, WebSearchTool, provideWebTools;
```

- [ ] **Step 2: 静态检查**

Run: `cd /Users/fitz/REPO/conatus && dart analyze packages/conatus_search`
Expected: `No issues found!`

- [ ] **Step 3: 跑整个包**

Run: `cd /Users/fitz/REPO/conatus && dart test packages/conatus_search`
Expected: 全部通过

- [ ] **Step 4: 提交**

```bash
git add packages/conatus_search/lib/conatus_search.dart
git commit -m "refactor(search): 收敛 barrel 导出"
```

---

## Task 12: conatus_code 与 example 调用点适配

**Files:**
- Modify: `packages/conatus_code/lib/src/tui/tui_app.dart`
- Modify: `packages/conatus_code/bin/conatus_code.dart`

- [ ] **Step 1: tui_app.dart 把凭据块前移并改 provideSearch 调用**

把 `packages/conatus_code/lib/src/tui/tui_app.dart` 中这一段（当前在 163–173 行附近）：

```dart
    if (webTools) {
      provideSearch(app, exaApiKey: exaApiKey);
      provideWebTools(app);
    }

    // ── 凭据 / 模型 / 自省 / 子 Agent ───────────────────────────
    // Key 统一经凭据服务：provider 与注册表都不直接读环境变量，换 config.toml /
    // File / Vault 等来源时只改这一处注入。缺省 EnvCredentials。
    final Credentials resolvedCredentials =
        provideCredentials(app, credentials: credentials);
    ProviderRegistry? registry;
```

替换为：

```dart
    // ── 凭据（先于联网工具：搜索源要经凭据服务解析 Key）──────────
    // Key 统一经凭据服务：provider、注册表与搜索源都不直接读环境变量，换
    // config.toml / File / Vault 等来源时只改这一处注入。缺省 EnvCredentials。
    final Credentials resolvedCredentials =
        provideCredentials(app, credentials: credentials);

    if (webTools) {
      provideSearch(app, credentials: resolvedCredentials);
      provideWebTools(app, credentials: resolvedCredentials);
    }

    // ── 模型 / 自省 / 子 Agent ─────────────────────────────────
    ProviderRegistry? registry;
```

- [ ] **Step 2: 删掉 create 的 exaApiKey 形参与文档注释**

在同一文件里，把 `create` 的形参 `String? exaApiKey,` 删掉，并把文档注释里这一行：

```dart
  /// （默认 `<cwd>/.conatus`）下；[webTools] 为 true 时注册 DuckDuckGo（有
  /// [exaApiKey] 则 Exa 优先）；[skills] 为 true 时从 `.conatus/skills` 等目录
```

改为：

```dart
  /// （默认 `<cwd>/.conatus`）下；[webTools] 为 true 时按 `kDefaultSearchOrder`
  /// 装配搜索源（缺 Key 的自动跳过，见 `conatus_search`）；[skills] 为 true 时
  /// 从 `.conatus/skills` 等目录
```

- [ ] **Step 3: bin 删掉实参**

`packages/conatus_code/bin/conatus_code.dart` 里删掉这一行：

```dart
    exaApiKey: Platform.environment['EXA_API_KEY'],
```

- [ ] **Step 4: 静态检查与测试**

Run: `cd /Users/fitz/REPO/conatus/packages/conatus_code && dart analyze && dart test`
Expected: `No issues found!` + `All tests passed!`

- [ ] **Step 5: 确认 example 无需改动**

Run: `cd /Users/fitz/REPO/conatus && dart analyze example`
Expected: `No issues found!`

`example/voice_plan_mode.dart` 用的是 `provideSearch(app)`（无参），新签名下依然合法：该 example 没有提供 `'credentials'` 服务，因此只有免 Key 的 DuckDuckGo 参与——与改动前行为一致，不需要修改。

- [ ] **Step 6: 提交**

```bash
git add packages/conatus_code/lib/src/tui/tui_app.dart \
        packages/conatus_code/bin/conatus_code.dart
git commit -m "refactor(code): 搜索源改用凭据服务，移除 exaApiKey 直读环境变量"
```

---

## Task 13: 文档

**Files:**
- Modify: `packages/conatus_search/README.md`
- Modify: `packages/conatus_search/CHANGELOG.md`
- Modify: `README.md`（根）
- Modify: `CHANGELOG.md`（根）

- [ ] **Step 1: 更新包 README**

`packages/conatus_search/README.md` 全量替换为：

```markdown
# conatus_search

conatus 的搜索能力缝：

- `SearchService` + 可插拔 `SearchProvider`，按名字顺序装配、逐个回退：
  内置 `tavily` / `exa` / `brave` / `duckduckgo`（DuckDuckGo 免 Key），
  缺凭据的源自动跳过
- 凭据统一经 `conatus_credentials`（`TAVILY_API_KEY` / `EXA_API_KEY` /
  `BRAVE_API_KEY`），**不直接读环境变量**
- `WebSearchTool` / `FetchUrlTool` 与 `provideWebTools`（注册 `web_search` /
  `fetch_url`）；`fetch_url` 缺省裸 http，配了 `FIRECRAWL_API_KEY` 时改走
  Firecrawl（返回 markdown）

```dart
import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_search/conatus_search.dart';

final Credentials credentials = provideCredentials(app);   // 缺省 EnvCredentials
provideSearch(app, credentials: credentials);               // 按 kDefaultSearchOrder
provideWebTools(app, credentials: credentials);

// 只要某几家、并改顺序：
provideSearch(app,
    order: <String>['brave', 'duckduckgo'], credentials: credentials);
```

搜索全失败时 `web_search` 返回 `SEARCH_UNAVAILABLE`，文案以「无法联网：所有搜索源
都不可用。」开头，并列出没配好的源（如 `exa（缺少 EXA_API_KEY）`）。
```

- [ ] **Step 2: 更新包 CHANGELOG**

`packages/conatus_search/CHANGELOG.md` 在 `## [0.15.0]` 之前插入：

```markdown
## [未发布]

- 新增 Tavily / Brave 两个 HTTP 搜索源；`SearchService` 暴露 `statuses`
  （装配期哪些源可用、哪些被跳过及原因）。
- 新增名字驱动的装配：`SearchProviderSpec` / `kSearchProviderSpecs` /
  `buildSearchProviders` / `kDefaultSearchOrder`；凭据统一经
  `conatus_credentials` 解析。
- 新增 `WebFetcher` 接缝：`HttpFetcher`（默认，stripHtml 迁入此文件）与
  `FirecrawlFetcher`（配 `FIRECRAWL_API_KEY` 时启用，返回 markdown）。
- `web_search` 全失败时返回 `SEARCH_UNAVAILABLE` 并给出明确「无法联网」文案与
  未配置源清单；`fetch_url` 失败文案同口径。
- **破坏性**：`provideSearch` 移除 `exaApiKey`，改为 `order` + `credentials`
  （缺省取上下文的 `'credentials'` 服务）；`provideWebTools` 新增可选
  `fetcher` / `credentials`。
```

- [ ] **Step 3: 更新根 README**

根 `README.md` 的 `### search — 搜索能力缝 + web 工具` 段落（约 530–539 行）替换为：

```markdown
### `search` — 搜索能力缝 + web 工具

服务键 `'search'`（`ctx.search`）。多个 `SearchProvider` 按名字顺序回退：内置
`tavily` / `exa` / `brave` / `duckduckgo`（免 Key），缺凭据的源自动跳过；凭据统一
经 `conatus_credentials` 解析。`provideWebTools` 把 `web_search` / `fetch_url`
两个只读工具注册进 `ctx.tools`，`fetch_url` 在有 `FIRECRAWL_API_KEY` 时改走
Firecrawl（返回 markdown）。

```dart
final credentials = provideCredentials(app);
provideSearch(app, credentials: credentials); // 顺序见 kDefaultSearchOrder
provideWebTools(app, credentials: credentials);
```
```

同时把根 README 的 API 表里 `provideSearch(ctx, {search, providers, exaApiKey})` 一行（约 1465 行）改为：

```markdown
| `provideSearch(ctx, {order, credentials, providers, search})` / `ctx.search` | 提供 `'search'` / 快捷访问；按 `order` 装配，缺凭据的源跳过 |
```

- [ ] **Step 4: 更新根 CHANGELOG**

根 `CHANGELOG.md` 的 `## [未发布]` 段落下新增：

```markdown
`conatus_search` 支持多 provider 搜索路由：

- 新增 Tavily / Brave 搜索源与名字驱动的装配（`buildSearchProviders` /
  `kDefaultSearchOrder`），凭据统一经 `conatus_credentials`；
  `provideSearch` 的 `exaApiKey` 参数被 `order` + `credentials` 取代
- 新增 `WebFetcher` 接缝与 Firecrawl 抓取后端，`fetch_url` 在有
  `FIRECRAWL_API_KEY` 时返回 markdown
- `web_search` 全失败时返回 `SEARCH_UNAVAILABLE`，文案明确「无法联网」并列出
  未配置的源
- `conatus_code` 的搜索装配改用凭据服务，`ConatusTuiRuntime.create` 不再有
  `exaApiKey` 参数
```

- [ ] **Step 5: 全量验证**

Run:
```bash
cd /Users/fitz/REPO/conatus && dart analyze && dart test packages/conatus_search && cd packages/conatus_code && dart analyze && dart test
```
Expected: 全部 `No issues found!` 与 `All tests passed!`

- [ ] **Step 6: 提交**

```bash
git add packages/conatus_search/README.md packages/conatus_search/CHANGELOG.md \
        README.md CHANGELOG.md
git commit -m "docs(search): 记录多 provider 搜索路由与新抓取接缝"
```

---

## 验收清单

- [ ] `dart analyze`（根 + `packages/conatus_code`）无 issue
- [ ] `dart test packages/conatus_search` 全绿（含新增的 6 个测试文件）
- [ ] `dart test`（`packages/conatus_code`）全绿
- [ ] 包内 `grep -rn "exaApiKey" packages/` 无残留
- [ ] 包内 `grep -rn "Platform.environment" packages/conatus_search packages/conatus_code` 无搜索相关残留
- [ ] `web_search` 失败文案含「无法联网」与未配置源清单
