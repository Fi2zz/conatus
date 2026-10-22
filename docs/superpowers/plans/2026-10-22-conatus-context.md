# conatus_context 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `conatus_context` 包：在工具结果进入会话日志前做确定性结构化压缩，并把原文存入可逆的 CCR 存储供模型按需取回。

**Architecture:** 六个纯函数压缩器（JSON / 日志 / 搜索 / diff / 表格 / 文本）由检测器按内容类型选取；`ContextRouter` 统一负责安全门、CCR 存取、标记注入、统计与 fail-open；`provideContextCompression` 把 Router 装成 `ToolRegistry` 中间件并注册 `context_retrieve` / `context_stats` 两个工具。

**Tech Stack:** Dart 3.11、`dart:convert`、`package:test`、`conatus_core` / `conatus_foundation` / `conatus_llm`，零新增运行时依赖。

**Spec:** `docs/superpowers/specs/2026-10-22-conatus-context-design.md`

## Global Constraints

- 所有 pubspec 的 `version: 0.16.0`、`publish_to: none`，包间依赖一律 `path`（见 `packages/conatus_compaction/pubspec.yaml`）。
- 零新增运行时依赖；只用 Dart 核心库与仓库内包。
- 单文件 ≤ 200 行、单 class ≤ 150 行、函数体 ≤ 40 行、函数参数 ≤ 4 个。
- 每个函数 `if/else/switch/case` 总数 ≤ 3，最大嵌套 ≤ 2，单条件 `&&/||` ≤ 2；禁止嵌套三元。
- 布尔成员/函数用具象状态词，不用 `is/has/can/should` 前缀；函数名 `动词 + 名词`。
- 包内相对导入；单引号；顶层函数与成员显式返回类型；优先 `final`。
- 面向用户的文案与文档注释用中文。
- 压缩器必须确定性、保序、不伪造事实；所有省略显式标注。
- 任何压缩失败一律 fail-open 返回原文，绝不向工具调用链抛异常。
- 提交信息：`feat(context): ...` / `test(context): ...` / `docs(context): ...`，中文描述。
- 每个任务完成前，把该任务新增的公共符号加入 `packages/conatus_context/lib/conatus_context.dart` 的 `export`；最终导出清单在 Task 16 收敛。

## Review Focus

1. 超长单行 JSON 或嵌套深度 > 32 的输入：压缩器必须透传，不能因重新编码而丢层级或抛错。
2. CRLF / BOM 输入：检测与行分割不能把 `\r` 混进关键字匹配，BOM 不能导致 JSON 误判为纯文本。
3. 模型编造或过期 `<<ctx:ID>>`：`context_retrieve` 必须返回可读失败，不抛异常、不泄露其他条目。
4. `context_retrieve` 的 `offset` / `limit` 边界（负数、越界、0）：不得崩溃或静默返回空。
5. 工具结果 `value` 不是 `Map`（List / int / null）：中间件合并元数据时不得抛类型异常。

---

### Task 1: 包骨架与公共类型

**Files:**
- Create: `packages/conatus_context/pubspec.yaml`
- Create: `packages/conatus_context/analysis_options.yaml`
- Create: `packages/conatus_context/CHANGELOG.md`
- Create: `packages/conatus_context/LICENSE`（复制仓库根 `LICENSE`）
- Create: `packages/conatus_context/lib/conatus_context.dart`
- Create: `packages/conatus_context/lib/src/content_kind.dart`
- Create: `packages/conatus_context/lib/src/context_compression_config.dart`
- Create: `packages/conatus_context/lib/src/compression_result.dart`
- Create: `packages/conatus_context/lib/src/compression_stats.dart`
- Test: `packages/conatus_context/test/types_test.dart`

**Interfaces:**
- Produces: `enum ContentKind { jsonArray, buildLog, searchResults, diff, tabular, text, sourceCode, passthrough }`
- Produces: `class ContextCompressionConfig`，字段与默认值严格按 spec §5.1，另加 `maxSearchFiles = 40`
- Produces: `class ContextCompressionResult`，字段 `applied / kind / content / beforeChars / afterChars / ccrId / skippedReason`
- Produces: `factory ContextCompressionResult.skipped({required String input, required ContentKind kind, required String reason})`
- Produces: `class KindStats` 与 `class CompressionStats`（`record` / `recordFailure` / `countCcrHit` / `toJson`）

- [ ] **Step 1: 建包骨架**

`pubspec.yaml`：

```yaml
name: conatus_context
description: >-
  conatus 的上下文压缩：在工具结果进入模型前按内容类型结构化压缩，
  原文落可逆 CCR 存储供按需取回。
version: 0.16.0
repository: https://github.com/Fi2zz/conatus
issue_tracker: https://github.com/Fi2zz/conatus/issues
publish_to: none

environment:
  sdk: ^3.6.0

resolution: workspace

dependencies:
  conatus_core: {path: ../conatus_core}
  conatus_foundation: {path: ../conatus_foundation}
  conatus_llm: {path: ../conatus_llm}

dev_dependencies:
  lints: ^4.0.0
  test: ^1.25.0

topics:
  - plugin
  - context
  - compression
  - tokens
```

`analysis_options.yaml` 与 `packages/conatus_compaction/analysis_options.yaml` 相同（只 include 根配置）。
`CHANGELOG.md` 首条写 `## 0.16.0` + 「初始版本：结构化压缩 + CCR 可逆取回」。

- [ ] **Step 2: 写失败测试**

```dart
test('默认配置与 spec 一致', () {
  const ContextCompressionConfig c = ContextCompressionConfig();
  expect(c.enabled, true);
  expect(c.minChars, 4000);
  expect(c.minSavingRatio, 0.15);
  expect(c.ccrMaxEntries, 1000);
  expect(c.ccrTtl, const Duration(hours: 1));
  expect(c.maxSearchFiles, 40);
  expect(c.textTargetRatio, 0.5);
});

test('跳过结果保留原文与长度', () {
  final ContextCompressionResult r = ContextCompressionResult.skipped(
    input: 'abc',
    kind: ContentKind.text,
    reason: 'tooSmall',
  );
  expect(r.applied, false);
  expect(r.content, 'abc');
  expect(r.afterChars, 3);
  expect(r.ccrId, isNull);
});

test('统计按类型累计并标注 estimated', () {
  final CompressionStats stats = CompressionStats();
  stats.record(ContextCompressionResult(
    applied: true,
    kind: ContentKind.jsonArray,
    content: 'x',
    beforeChars: 100,
    afterChars: 20,
    ccrId: 'a',
  ), ccrStored: true);
  stats.recordFailure(ContentKind.buildLog);
  stats.countCcrHit();
  final Map<String, Object?> json = stats.toJson();
  expect(stats.applied, 1);
  expect(stats.failures, 1);
  expect(stats.ccrStored, 1);
  expect(stats.ccrHits, 1);
  expect(json['estimated'], true);
  expect((json['byKind'] as Map<String, Object?>)['jsonArray'], isNotNull);
});
```

- [ ] **Step 3: 运行测试确认失败**

Run: `cd packages/conatus_context && dart test test/types_test.dart`
Expected: 编译失败，`ContentKind` / `ContextCompressionConfig` 未定义。

- [ ] **Step 4: 实现类型文件**

`CompressionStats.toJson()` 结构：

```dart
<String, Object?>{
  'estimated': true,
  'tokenEstimator': 'chars/4',
  'applied': applied,
  'skipped': skipped,
  'failures': failures,
  'beforeChars': beforeChars,
  'afterChars': afterChars,
  'savedChars': beforeChars - afterChars,
  'ccrStored': ccrStored,
  'ccrHits': ccrHits,
  'byKind': <String, Object?>{
    for (final MapEntry<ContentKind, KindStats> e in byKind.entries)
      e.key.name: e.value.toJson(),
  },
}
```

`lib/conatus_context.dart` 先只导出这四个文件。

- [ ] **Step 5: 跑测试并提交**

Run: `cd packages/conatus_context && dart test test/types_test.dart && dart analyze`
Expected: 全部通过，analyze 无输出。

```bash
git add packages/conatus_context
git commit -m "feat(context): 建立 conatus_context 包与公共类型"
```

---

### Task 2: 内容检测器

**Files:**
- Create: `packages/conatus_context/lib/src/content_detector.dart`
- Test: `packages/conatus_context/test/content_detector_test.dart`

**Interfaces:**
- Produces: `class ContentDetection { final ContentKind kind; final double confidence; final List<String> signals; }`
- Produces: `ContentDetection detectContent(String input)`，纯函数、无 I/O、确定性
- Produces: `typedef Detector = ContentDetection Function(String input);`

- [ ] **Step 1: 写失败测试**

覆盖：JSON 数组、pytest / npm / cargo 日志、Unix 与 Windows 搜索行、含 `-` 的文件名、unified diff、CSV、markdown 表格、Dart/Python 源码、`git status`、纯文本、BOM 开头的 JSON。

```dart
test('BOM 开头的 JSON 数组仍识别为 jsonArray', () {
  expect(detectContent('\uFEFF[{"a":1},{"a":2},{"a":3}]').kind,
      ContentKind.jsonArray);
});

test('git status 优先于其它信号', () {
  const String input = 'On branch main\n'
      'Changes not staged for commit:\n'
      '\tmodified:   lib/a.dart\n\n'
      'diff --git a/lib/a.dart b/lib/a.dart\n';
  expect(detectContent(input).kind, ContentKind.passthrough);
});

test('Windows 路径与含连字符文件名识别为搜索结果', () {
  const String input = 'C:\\src\\pre-commit.dart:12:foo\n'
      'C:\\src\\pre-commit.dart:13:bar\n'
      'C:\\src\\pre-commit.dart:14:baz\n';
  expect(detectContent(input).kind, ContentKind.searchResults);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd packages/conatus_context && dart test test/content_detector_test.dart`
Expected: FAIL，`detectContent` 未定义。

- [ ] **Step 3: 实现检测器**

固定顺序与阈值：`git status` → `diff` → `searchResults`（≥3 行）→ `buildLog` → `jsonArray` → `tabular` → `sourceCode` → `text`。

- 先 `input = input.startsWith('\uFEFF') ? input.substring(1) : input;`
- `git status` 用「`On branch` / `HEAD detached` 头 + 至少一个 `Changes ...:` 或 `Untracked files:` 分节」双条件。
- 搜索行正则按「最早出现的 `分隔符+数字+分隔符`」锚定，兼容 `C:\` 与含 `-` 文件名。
- `jsonArray`：`trimLeft().startsWith('[')` 且 `jsonDecode` 成功且是 `List` 且长度 ≥ 3。
- `sourceCode` 只用于透传：缩进行占比 ≥ 30% 且命中 `class|def|func|fn |import |#include|=>|{}` 中至少 2 类。
- 不实现混合内容切分。

- [ ] **Step 4: 跑测试**

Run: `cd packages/conatus_context && dart test test/content_detector_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_context/lib/src/content_detector.dart packages/conatus_context/test/content_detector_test.dart
git commit -m "feat(context): 增加内容类型检测器"
```

---

### Task 3: CCR 标记、ID 与内存存储

**Files:**
- Create: `packages/conatus_context/lib/src/ccr_marker.dart`
- Create: `packages/conatus_context/lib/src/ccr_store.dart`
- Create: `packages/conatus_context/lib/src/ccr_memory_store.dart`
- Test: `packages/conatus_context/test/ccr_marker_test.dart`
- Test: `packages/conatus_context/test/ccr_memory_store_test.dart`

**Interfaces:**
- Produces: `String ccrIdOf(String content)`（16 位小写 hex）
- Produces: `const String kCcrMarkerPrefix = '<<ctx:'`
- Produces: `String encodeCcrMarker(String id, int omitted, String unit)` → `<<ctx:ID N_unit_omitted>>`
- Produces: `class CcrMarker { final String id; final int omitted; final String unit; }`
- Produces: `CcrMarker? parseCcrMarker(String content)`（取第一个匹配）
- Produces: `bool containsCcrMarker(String content)`
- Produces: `class CcrEntry { final String id; final int chars; final DateTime createdAt; final DateTime lastAccess; final int hits; }`
- Produces: `abstract class CcrStore { Future<String> put(String content); Future<String?> get(String id); Future<CcrEntry?> stat(String id); Future<void> remove(String id); Future<void> clear(); int get hits; int get length; }`
- Produces: `class CcrMemoryStore implements CcrStore`，构造参数 `{int maxEntries = 1000, Duration ttl = const Duration(hours: 1), DateTime Function()? now}`

- [ ] **Step 1: 写失败测试**

```dart
test('ID 稳定且为 16 位小写 hex', () {
  final String id = ccrIdOf('hello');
  expect(id, hasLength(16));
  expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(id), true);
  expect(ccrIdOf('hello'), id);
  expect(ccrIdOf('hello!'), isNot(id));
});

test('标记可编码、解析、检测', () {
  final String marker = encodeCcrMarker('0123456789abcdef', 42, 'items');
  expect(marker, '<<ctx:0123456789abcdef 42_items_omitted>>');
  expect(containsCcrMarker('a $marker b'), true);
  expect(parseCcrMarker('a $marker b')!.omitted, 42);
  expect(parseCcrMarker('无标记'), isNull);
});

test('内存存储往返字节相等并计数命中', () async {
  final CcrMemoryStore store = CcrMemoryStore();
  final String id = await store.put('原文\n第二行');
  expect(await store.get(id), '原文\n第二行');
  expect(store.hits, 1);
  expect(store.length, 1);
});

test('TTL 过期视为未命中', () async {
  DateTime now = DateTime(2026);
  final CcrMemoryStore store =
      CcrMemoryStore(ttl: const Duration(seconds: 10), now: () => now);
  final String id = await store.put('x');
  now = now.add(const Duration(seconds: 11));
  expect(await store.get(id), isNull);
});

test('超过容量淘汰最久未访问项', () async {
  final CcrMemoryStore store = CcrMemoryStore(maxEntries: 2);
  final String a = await store.put('a');
  final String b = await store.put('b');
  await store.get(a);
  final String c = await store.put('c');
  expect(await store.get(b), isNull);
  expect(await store.get(a), 'a');
  expect(await store.get(c), 'c');
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd packages/conatus_context && dart test test/ccr_marker_test.dart test/ccr_memory_store_test.dart`
Expected: FAIL，类型未定义。

- [ ] **Step 3: 实现**

ID：对 UTF-8 字节做 FNV-1a 64 与 djb2，各取 32 位，拼成 16 位 hex（小写、左侧补零）。
内存存储用 `LinkedHashMap<String, _MemoryEntry>`：`get` 命中时刷新 `lastAccess`/`hits` 并移到末尾；
`put` 前先清理过期项，再按容量从头部淘汰；`stat` 不刷新访问；`remove`/`clear` 幂等。

- [ ] **Step 4: 跑测试**

Run: `cd packages/conatus_context && dart test test/ccr_marker_test.dart test/ccr_memory_store_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_context/lib/src/ccr_*.dart packages/conatus_context/test/ccr_*_test.dart
git commit -m "feat(context): 增加 CCR 标记与内存存储"
```

---

### Task 4: 压缩器能力缝与 JSON 数组压缩器

**Files:**
- Create: `packages/conatus_context/lib/src/content_compressor.dart`
- Create: `packages/conatus_context/lib/src/compressors/json_array_compressor.dart`
- Test: `packages/conatus_context/test/json_array_compressor_test.dart`

**Interfaces:**
- Produces: `class CompressionBudget { final int maxItems; final int maxLines; final int maxFiles; final double targetRatio; final String retrievalId; final bool conservative; }`
- Produces: `class CompressionDraft { final String output; final int itemsOmitted; final String unit; }`
- Produces: `abstract class ContentCompressor { ContentKind get kind; CompressionDraft? compress(String input, CompressionBudget budget); }`
- Produces: `class JsonArrayCompressor implements ContentCompressor`，`kind => ContentKind.jsonArray`

- [ ] **Step 1: 写失败测试**

```dart
const CompressionBudget budget = CompressionBudget(
  maxItems: 10,
  maxLines: 100,
  maxFiles: 10,
  targetRatio: 0.5,
  retrievalId: '0123456789abcdef',
);

test('保留错误项与首尾项，输出仍是合法 JSON', () {
  final List<Map<String, Object?>> items = <Map<String, Object?>>[
    for (int i = 0; i < 100; i++)
      <String, Object?>{'id': i, 'status': i == 50 ? 500 : 200, 'name': 'n$i'},
  ];
  final CompressionDraft draft =
      JsonArrayCompressor().compress(jsonEncode(items), budget)!;
  final List<Object?> decoded = jsonDecode(draft.output) as List<Object?>;
  expect(decoded.length, lessThanOrEqualTo(11)); // 10 + 说明项
  expect(draft.output, contains('"status":500'));
  expect(draft.output, contains('"id":0'));
  expect(draft.output, contains('"id":99'));
  expect(draft.output, contains('<<ctx:0123456789abcdef'));
  expect(draft.itemsOmitted, greaterThan(0));
});

test('重复字符串去重并保持顺序', () {
  final String input = jsonEncode(<String>[
    for (int i = 0; i < 50; i++) i.isEven ? 'same' : 'v$i',
  ]);
  final CompressionDraft draft =
      JsonArrayCompressor().compress(input, budget)!;
  expect(draft.output.split('same').length - 1, 1);
});

test('深度超过 32 的 JSON 透传', () {
  final String deep =
      '${List<String>.filled(40, '[').join()}1${List<String>.filled(40, ']').join()}';
  expect(JsonArrayCompressor().compress(deep, budget), isNull);
});

test('非法 JSON 返回 null', () {
  expect(JsonArrayCompressor().compress('[1,2', budget), isNull);
});

test('元素不超过上限时只紧凑化，不省略', () {
  final CompressionDraft draft = JsonArrayCompressor()
      .compress('[ {"a": 1} , {"a": 2} ]', budget)!;
  expect(draft.itemsOmitted, 0);
  expect(draft.output, '[{"a":1},{"a":2}]');
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd packages/conatus_context && dart test test/json_array_compressor_test.dart`
Expected: FAIL，类型未定义。

- [ ] **Step 3: 实现**

算法按 spec §7.1：

1. 去 BOM；`jsonDecode`；必须是顶层 `List`；深度 > 32 → `null`。
2. 分类 dict / string / number / mixed；用 `jsonEncode`（键顺序取解析后的 Map 顺序）做去重键。
3. 必留：前 2、后 2、错误信号项、数值字段 1%/99% 外异常项（样本 ≥ 20）。
4. 其余按等距步长采样，回填后按原索引排序。
5. 输出紧凑 JSON；若 `itemsOmitted > 0` 且 `budget.retrievalId` 非空，末尾追加说明元素：
   dict → `{"_conatus_context":"<n> items omitted; context_retrieve id=<id>"}`；
   其它 → 同文案字符串。`retrievalId` 为空时文案去掉 `id=` 部分。
6. 省略数 = 原长度 - 输出元素数（不含说明元素）。

- [ ] **Step 4: 跑测试**

Run: `cd packages/conatus_context && dart test test/json_array_compressor_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_context/lib/src/content_compressor.dart packages/conatus_context/lib/src/compressors/json_array_compressor.dart packages/conatus_context/test/json_array_compressor_test.dart
git commit -m "feat(context): 增加 JSON 数组结构化压缩器"
```

---

### Task 5: Router（安全门、CCR、标记、统计、fail-open）

**Files:**
- Create: `packages/conatus_context/lib/src/context_router.dart`
- Test: `packages/conatus_context/test/context_router_test.dart`

**Interfaces:**
- Consumes: Task 1–4 的全部类型
- Produces: `class ContextRouter { ContextRouter({required ContextCompressionConfig config, required CcrStore store, Detector? detector, List<ContentCompressor>? compressors, CompressionStats? stats}); Future<ContextCompressionResult> compress(String input, {required String toolName, bool conservative = false}); }`
- Produces: getters `config` / `store` / `stats`

- [ ] **Step 1: 写失败测试**

测试文件顶部定义三个替身（都只处理 `ContentKind.text`，除 JSON 用例按需覆盖 kind）：

```dart
class _FakeCompressor implements ContentCompressor {
  _FakeCompressor({this.kind = ContentKind.text});
  @override
  final ContentKind kind;
  @override
  CompressionDraft? compress(String input, CompressionBudget budget) =>
      CompressionDraft('压缩后', itemsOmitted: 90, unit: 'items');
}

class _IdentityCompressor implements ContentCompressor {
  @override
  ContentKind get kind => ContentKind.text;
  @override
  CompressionDraft? compress(String input, CompressionBudget budget) =>
      CompressionDraft(input);
}

class _ThrowingCompressor implements ContentCompressor {
  @override
  ContentKind get kind => ContentKind.text;
  @override
  CompressionDraft? compress(String input, CompressionBudget budget) =>
      throw StateError('boom');
}

ContextRouter _router({
  Set<String> protectedTools = const <String>{},
  Set<ContentKind> disabledKinds = const <ContentKind>{},
  List<ContentCompressor>? compressors,
}) =>
    ContextRouter(
      config: ContextCompressionConfig(
        minChars: 10,
        protectedTools: protectedTools,
        disabledKinds: disabledKinds,
      ),
      store: CcrMemoryStore(),
      compressors: compressors ?? <ContentCompressor>[_FakeCompressor()],
    );
```

覆盖：

```dart
test('低于最小尺寸直接透传', () async {
  final ContextRouter router = _router(); // minChars: 10
  final ContextCompressionResult r =
      await router.compress('short', toolName: 't');
  expect(r.applied, false);
  expect(r.skippedReason, 'tooSmall');
});

test('保护工具与禁用类型透传', () async {
  final ContextRouter router = _router(protectedTools: {'secret'});
  expect((await router.compress(List<String>.filled(100, 'x').join(), toolName: 'secret')).skippedReason,
      'protected');
  final ContextRouter disabled =
      _router(disabledKinds: {ContentKind.jsonArray});
  final ContextCompressionResult r = await disabled.compress(
      jsonEncode(List<Map<String, Object?>>.filled(5, {'a': 1})),
      toolName: 't');
  expect(r.skippedReason, 'disabled');
});

test('已含标记的输入不再压缩', () async {
  final ContextRouter router = _router();
  final ContextCompressionResult r = await router.compress(
      List<String>.filled(100, 'x').join() + ' <<ctx:0123456789abcdef 1_items_omitted>>',
      toolName: 't');
  expect(r.skippedReason, 'alreadyCompressed');
});

test('应用压缩时存入原文并注入标记', () async {
  final ContextRouter router = _router(
      compressors: <ContentCompressor>[
        _FakeCompressor(kind: ContentKind.jsonArray),
      ]);
  final ContextCompressionResult r = await router.compress(
      jsonEncode(List<Map<String, Object?>>.filled(50, {'a': 'b'})),
      toolName: 't');
  expect(r.applied, true);
  expect(r.content, contains('<<ctx:'));
  expect(await router.store.get(r.ccrId!), isNotEmpty);
  expect(router.stats.ccrStored, 1);
});

test('压缩器抛错时 fail-open 并计数', () async {
  final ContextRouter router = _router(compressors: [_ThrowingCompressor()]);
  final ContextCompressionResult r =
      await router.compress(List<String>.filled(1000, 'x').join(), toolName: 't');
  expect(r.applied, false);
  expect(r.content, List<String>.filled(1000, 'x').join());
  expect(r.skippedReason, 'error');
  expect(router.stats.failures, 1);
});

test('收益不足回退原文', () async {
  final ContextRouter router = _router(compressors: [_IdentityCompressor()]);
  final ContextCompressionResult r =
      await router.compress(List<String>.filled(1000, 'x').join(), toolName: 't');
  expect(r.skippedReason, 'noSaving');
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd packages/conatus_context && dart test test/context_router_test.dart`
Expected: FAIL。

- [ ] **Step 3: 实现**

顺序：`enabled` → 空串 → 保护工具 → `length < minChars` → 标记幂等 → 检测 → kind 禁用 /
`sourceCode` / `passthrough` → 构造 budget（`retrievalId = ccrEnabled ? ccrIdOf(input) : ''`）→
查找同 kind 压缩器（无则 `disabled`）→ try/catch → `draft == null` 记 `noSaving` →
需要省略且开启 CCR 时 `store.put(input)` → 追加标记（输出已含标记则不重复）→
收益门槛 → 统计。

`skippedReason` 取值固定：`tooSmall / protected / disabled / alreadyCompressed / noSaving / error / empty`。
`ccrId` 仅在 `applied && ccrStored` 时非空。

- [ ] **Step 4: 跑测试**

Run: `cd packages/conatus_context && dart test test/context_router_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_context/lib/src/context_router.dart packages/conatus_context/test/context_router_test.dart
git commit -m "feat(context): 增加压缩路由与安全门"
```

---

### Task 6: 文件型 CCR 存储

**Files:**
- Create: `packages/conatus_context/lib/src/ccr_file_store.dart`
- Test: `packages/conatus_context/test/ccr_file_store_test.dart`

**Interfaces:**
- Produces: `class CcrFileStore implements CcrStore`，构造 `{required FileSystem fs, required String dir, int maxEntries = 1000, Duration ttl = const Duration(hours: 1), DateTime Function()? now}`
- 同时提供 `String contextCacheDir()`，返回 `'${resolveConatusHome()}/context-cache'`

- [ ] **Step 1: 写失败测试**

用 `LocalFileSystem` + `Directory.systemTemp.createTempSync()`，`addTearDown` 删除目录。

```dart
late Directory tmp;
late LocalFileSystem fs;
late CcrFileStore store;

setUp(() {
  tmp = Directory.systemTemp.createTempSync('ctx_ccr');
  fs = LocalFileSystem();
  store = CcrFileStore(fs: fs, dir: tmp.path);
});

tearDown(() => tmp.deleteSync(recursive: true));

test('往返字节相等，重启后可读', () async {
  final String id = await store.put('原文\nline2');
  final CcrFileStore second = CcrFileStore(fs: fs, dir: tmp.path);
  expect(await second.get(id), '原文\nline2');
});

test('内容被篡改视为未命中', () async {
  final String id = await store.put('original');
  await fs.writeText(await fs.resolve('${tmp.path}/$id.txt'), 'tampered');
  expect(await CcrFileStore(fs: fs, dir: tmp.path).get(id), isNull);
});

test('目录不存在时按空存储启动，put 时创建', () async {
  final CcrFileStore s = CcrFileStore(fs: fs, dir: '${tmp.path}/missing');
  expect(s.length, 0);
  final String id = await s.put('x');
  expect(await s.get(id), 'x');
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd packages/conatus_context && dart test test/ccr_file_store_test.dart`
Expected: FAIL。

- [ ] **Step 3: 实现**

- 目录：`final FsTarget root = await fs.resolve(dir);`
- 懒加载 `_ensureLoaded()`：读 `index.json`（不存在或解析失败 → 空索引），剔除 `stat` 缺失或
  `chars` 不符的条目。`listDir` 抛错时按空目录处理。
- `put`：`id = ccrIdOf(content)`；写 `<dir>/<id>.txt`；更新索引（`createdAt/lastAccess/hits/chars`）；
  清理过期与超容量；`index.json` 与内容文件都用 `fs.writeText` 原子写。
- `get`：校验文件内容 `ccrIdOf(content) == id`；命中则更新索引并返回，否则 `null`。
- `remove` / `clear`：删除内容文件与索引项；`clear` 后 `length == 0`。
- 所有索引写入失败 fail-open（内存索引继续工作），不抛给调用方。

- [ ] **Step 4: 跑测试**

Run: `cd packages/conatus_context && dart test test/ccr_file_store_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_context/lib/src/ccr_file_store.dart packages/conatus_context/test/ccr_file_store_test.dart
git commit -m "feat(context): 增加文件型 CCR 存储"
```

---

### Task 7: `context_retrieve` 与 `context_stats` 工具

**Files:**
- Create: `packages/conatus_context/lib/src/context_retrieval_tool.dart`
- Create: `packages/conatus_context/lib/src/context_stats_tool.dart`
- Test: `packages/conatus_context/test/context_tools_test.dart`

**Interfaces:**
- Produces: `class ContextRetrievalTool extends Tool`，`ContextRetrievalTool(this.store)`，`name => 'context_retrieve'`
- Produces: `class ContextStatsTool extends Tool`，`ContextStatsTool(this.stats)`，`name => 'context_stats'`
- 参数：`id`（string，必填）、`offset`（integer，可选）、`limit`（integer，默认 40000）

- [ ] **Step 1: 写失败测试**

```dart
test('按 id 取回原文并返回元数据', () async {
  final CcrMemoryStore store = CcrMemoryStore();
  final String id = await store.put('0123456789');
  final ToolResult r = await ContextRetrievalTool(store)
      .call(const ToolContext(ToolCall(name: 'context_retrieve', arguments: {'id': id})));
  expect(r.isError, false);
  expect(r.content, '0123456789');
});

test('offset 与 limit 正确切片，越界不崩溃', () async {
  final String id = await store.put('abcdefghij');
  Future<ToolResult> call(Map<String, Object?> args) => ContextRetrievalTool(store)
      .call(ToolContext(ToolCall(name: 'context_retrieve', arguments: {'id': id, ...args})));
  expect((await call({'offset': 2, 'limit': 3})).content, 'cde');
  expect((await call({'offset': -5})).content, 'abcdefghij');
  expect((await call({'offset': 100})).isError, true);
  expect((await call({'limit': 0})).content, 'abcdefghij');
});

test('编造 id 返回可读失败而非异常', () async {
  final ToolResult r = await ContextRetrievalTool(store)
      .call(const ToolContext(ToolCall(name: 'context_retrieve', arguments: {'id': 'ffffffffffffffff'})));
  expect(r.isError, true);
  expect(r.content, contains('未找到'));
  expect(r.error!.code, 'ccr_miss');
});

test('stats 工具输出 estimated 标记', () async {
  final ToolResult r = await ContextStatsTool(CompressionStats())
      .call(const ToolContext(ToolCall(name: 'context_stats')));
  expect(jsonDecode(r.content)['estimated'], true);
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd packages/conatus_context && dart test test/context_tools_test.dart`
Expected: FAIL。

- [ ] **Step 3: 实现**

- `offset`：`< 0` 归 0；`> length` → `ToolResult.failure('偏移超出原文长度', error: const ToolError('ccr_offset', 'offset 超出原文长度'))`。
- `limit`：`<= 0` 或 `> 40000` → 40000。
- 成功：`ToolResult.success(片段, value: {'id': id, 'chars': total, 'offset': start, 'returned': part.length, 'truncated': end < total})`。
- 未命中：`ToolResult.failure('未找到 id=...；可能已过期，或标记不是由本会话产生', error: const ToolError('ccr_miss', '未找到该 id 的原文'))`。
- 描述里写明标记格式与用法，便于模型理解。

- [ ] **Step 4: 跑测试**

Run: `cd packages/conatus_context && dart test test/context_tools_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_context/lib/src/context_retrieval_tool.dart packages/conatus_context/lib/src/context_stats_tool.dart packages/conatus_context/test/context_tools_test.dart
git commit -m "feat(context): 增加 CCR 取回与统计工具"
```

---

### Task 8: 装配与工具结果中间件

**Files:**
- Create: `packages/conatus_context/lib/src/provide_context_compression.dart`
- Test: `packages/conatus_context/test/provide_context_compression_test.dart`

**Interfaces:**
- Produces: `class ContextCompressionService { final ContextRouter router; final CompressionStats stats; final CcrStore store; }`
- Produces: `ContextCompressionService provideContextCompression(Context ctx, {ContextCompressionConfig? config, CcrStore? store, ToolRegistry? tools, FileSystem? fs, String? dir, List<ContentCompressor>? compressors})`
- Produces: `extension ContextCompressionContext on Context { ContextCompressionService? get contextCompressor; }`
- 中间件 tag：`'contextCompression'`

- [ ] **Step 1: 写失败测试**

用假压缩器避免依赖 Task 10+。测试文件内定义：

```dart
class _HeadCompressor implements ContentCompressor {
  @override
  ContentKind get kind => ContentKind.text;
  @override
  CompressionDraft? compress(String input, CompressionBudget budget) =>
      CompressionDraft(input.substring(0, 10), itemsOmitted: 90);
}

class _EchoTool extends Tool {
  @override
  String get name => 'echo';
  @override
  String get description => 'echo';
  @override
  List<ParamSpec> get params => <ParamSpec>[ParamSpec.string('text')];
  @override
  Future<ToolResult> call(ToolContext context) async =>
      ToolResult.success(context.str('text'), value: <String, Object?>{'ok': true});
}

class _ListValueTool extends Tool {
  @override
  String get name => 'list';
  @override
  String get description => 'list value';
  @override
  Future<ToolResult> call(ToolContext context) async =>
      ToolResult.success(List<String>.filled(100, 'x').join(), value: <Object?>[1, 2, 3]);
}
```

```dart
Context _app({
  ContextCompressionConfig? config,
  List<ContentCompressor>? compressors,
}) {
  final Context app = Context.root();
  provideTools(app);
  app.effect(() => app.tools.register(_EchoTool()));
  app.effect(() => app.tools.register(_ListValueTool()));
  provideContextCompression(app,
      config: config ?? const ContextCompressionConfig(minChars: 10),
      compressors: compressors ?? <ContentCompressor>[_HeadCompressor()]);
  addTearDown(app.dispose);
  return app;
}

test('中间件压缩结果并合并元数据', () async {
  final Context app = _app();
  final ToolResult r = await app.tools
      .call(const ToolCall(name: 'echo', arguments: {'text': List<String>.filled(100, 'x').join()}));
  expect(r.content, contains('<<ctx:'));
  expect((r.value! as Map<String, Object?>)['contextCompressed'], true);
  expect((r.value! as Map<String, Object?>)['ok'], true);
});

test('value 不是 Map 时不抛异常', () async {
  final Context app = _app();
  final ToolResult r = await app.tools.call(const ToolCall(name: 'list'));
  expect(r.isError, false);
  expect(r.content, contains('<<ctx:'));
  final Map<String, Object?> value = r.value! as Map<String, Object?>;
  expect(value['originalValue'], <Object?>[1, 2, 3]);
});

test('enabled=false 时完全透传', () async {
  final Context app = _app(
      config: const ContextCompressionConfig(minChars: 10, enabled: false));
  final ToolResult r = await app.tools
      .call(const ToolCall(name: 'echo', arguments: {'text': List<String>.filled(100, 'x').join()}));
  expect(r.content, List<String>.filled(100, 'x').join());
});

test('保护工具透传', () async {
  final Context app = _app(
      config: const ContextCompressionConfig(
          minChars: 10, protectedTools: <String>{'echo'}));
  final ToolResult r = await app.tools
      .call(const ToolCall(name: 'echo', arguments: {'text': List<String>.filled(100, 'x').join()}));
  expect(r.content, List<String>.filled(100, 'x').join());
});

test('上下文释放后中间件与工具撤销', () async {
  final Context base = Context.root();
  provideTools(base);
  base.effect(() => base.tools.register(_EchoTool()));
  final Context child = Context(parent: base);
  provideContextCompression(child,
      config: const ContextCompressionConfig(minChars: 10),
      compressors: <ContentCompressor>[_HeadCompressor()]);
  expect(base.tools.get('context_retrieve'), isNotNull);
  child.dispose();
  expect(base.tools.get('context_retrieve'), isNull);
  final ToolResult r = await base.tools
      .call(const ToolCall(name: 'echo', arguments: {'text': List<String>.filled(100, 'x').join()}));
  expect(r.content, List<String>.filled(100, 'x').join());
  base.dispose();
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd packages/conatus_context && dart test test/provide_context_compression_test.dart`
Expected: FAIL。

- [ ] **Step 3: 实现**

- 配置优先级：显式 `config` > `ctx.get<ContextCompressionConfig>('contextCompressionConfig')` > 默认值。
- store：显式 `store` > `dir != null` 时 `CcrFileStore(fs: fs ?? ctx.require('fs'), dir: dir)` > `CcrMemoryStore(maxEntries, ttl)`。
- 中间件：
  - `config.enabled == false` 或工具受保护 → 直接 `next()`；
  - `result.isError && !compressToolErrors` → 透传；
  - `router.compress(...)`；
  - 未应用 → 原结果；
  - 应用 → `ToolResult(content, value: {...原 value 若是 Map, ...元数据})`；`value` 不是 Map 时
    新建 `<String, Object?>{'originalValue': result.value, ...元数据}`，不抛错。
- `ctx.effect(() => registry.use(..., tag: 'contextCompression'))`；
- `ctx.effect(() => registry.register(ContextRetrievalTool(store)))`（仅 `ccrEnabled`）；
- `ctx.effect(() => registry.register(ContextStatsTool(stats)))`；
- `ctx.provide('contextCompressor', service)`。

- [ ] **Step 4: 跑测试**

Run: `cd packages/conatus_context && dart test test/provide_context_compression_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_context/lib/src/provide_context_compression.dart packages/conatus_context/test/provide_context_compression_test.dart
git commit -m "feat(context): 装配工具结果压缩中间件"
```

---

### Task 9: 非 Agent 入口 `compressMessages`

**Files:**
- Create: `packages/conatus_context/lib/src/compress_messages.dart`
- Test: `packages/conatus_context/test/compress_messages_test.dart`

**Interfaces:**
- Produces: `Future<List<LlmMessage>> compressMessages(List<LlmMessage> messages, {ContextCompressionConfig? config, CcrStore? store, List<ContentCompressor>? compressors, Set<String> roles = const <String>{'tool'}})`

- [ ] **Step 1: 写失败测试**

```dart
test('只压缩指定 role 的消息并保留全部字段', () async {
  final List<LlmMessage> out = await compressMessages(<LlmMessage>[
    LlmMessage('user', List<String>.filled(1000, 'x').join()),
    LlmMessage('tool', jsonEncode(List<Map<String, Object?>>.filled(50, {'a': 'b'})),
        toolCallId: 'c1'),
  ], compressors: [JsonArrayCompressor()]);
  expect(out[0].content, List<String>.filled(1000, 'x').join());
  expect(out[1].content, contains('<<ctx:'));
  expect(out[1].toolCallId, 'c1');
});

test('重复调用结果不变（幂等）', () async {
  final List<LlmMessage> input = <LlmMessage>[
    LlmMessage('tool',
        jsonEncode(List<Map<String, Object?>>.filled(50, {'a': 'b'})),
        toolCallId: 'c1'),
  ];
  final List<LlmMessage> once =
      await compressMessages(input, compressors: [JsonArrayCompressor()]);
  final List<LlmMessage> twice =
      await compressMessages(once, compressors: [JsonArrayCompressor()]);
  expect(twice.single.content, once.single.content);
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd packages/conatus_context && dart test test/compress_messages_test.dart`
Expected: FAIL。

- [ ] **Step 3: 实现**

内部建一个临时 `ContextRouter`（store 缺省 `CcrMemoryStore`），逐条按 role 过滤后调用
`compress(content, toolName: 'llm_message')`；重建 `LlmMessage` 时原样带上
`toolCalls / toolCallId / cacheable / images / thinkingBlocks`。

- [ ] **Step 4: 跑测试**

Run: `cd packages/conatus_context && dart test test/compress_messages_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_context/lib/src/compress_messages.dart packages/conatus_context/test/compress_messages_test.dart
git commit -m "feat(context): 增加 compressMessages 纯函数入口"
```

---

### Task 10: 构建/测试日志压缩器

**Files:**
- Create: `packages/conatus_context/lib/src/text_lines.dart`
- Create: `packages/conatus_context/lib/src/compressors/build_log_compressor.dart`
- Test: `packages/conatus_context/test/build_log_compressor_test.dart`

**Interfaces:**
- Produces: `List<String> splitTextLines(String input)`（去 `\r`，不保留行尾）
- Produces: `String joinTextLines(List<String> lines, {required bool crlf})`
- Produces: `class BuildLogCompressor implements ContentCompressor`，`kind => ContentKind.buildLog`

- [ ] **Step 1: 写失败测试**

样本 1：1200 行 pytest 日志，其中 3 行 `ERROR`、1 段 `Traceback`、末尾 `2 failed, 100 passed`。
断言：ERROR 行全在、`Traceback` 起止帧在、摘要行在、总行数 ≤ `maxLines + 省略标记行数`。

样本 2：npm 日志含 `npm ERR!` 与重复 `WARN`。
断言：WARN 去重后只留 1 条、`npm ERR!` 全留。

样本 3：CRLF 输入。断言输出仍含 `\r\n`，且错误行不丢。

样本 4：cargo 的 `error[E0425]` 与 `--> src/main.rs:3:5` 保留。

- [ ] **Step 2: 运行确认失败**

Run: `cd packages/conatus_context && dart test test/build_log_compressor_test.dart`
Expected: FAIL。

- [ ] **Step 3: 实现**

格式识别 + 行级打分 + 选择按 spec §7.2：

- 级别正则：`\b(FATAL|ERROR|FAIL|WARN|WARNING|INFO|DEBUG|TRACE)\b`（大小写不敏感，`FAIL` 与 `ERROR` 同分）。
- 栈识别：`Traceback (most recent call last)`、`^\s+at `、`^\s+File "`、`^--> `、`^\s+\|`。
  Python 栈在「已出现缩进帧后遇到非缩进非空行」结束；中间空行不结束。
- 摘要：`\d+ (passed|failed|errors?)`、`Tests?:\s`、`BUILD (SUCCESS|FAILED)`、`make: \*\*\*`。
- 选择顺序：错误/失败 → 栈整段 → 摘要 → WARN（去重）→ 每选中行 ±2 行上下文；
  超预算先丢上下文，再丢 INFO/DEBUG，最后才丢 WARN；错误与栈永不丢。
- 保守模式：`maxLines ~/ 2`，上下文 ±1，WARN/INFO 全丢。
- 用 `splitTextLines` / `joinTextLines` 保持 CRLF。

- [ ] **Step 4: 跑测试**

Run: `cd packages/conatus_context && dart test test/build_log_compressor_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_context/lib/src/text_lines.dart packages/conatus_context/lib/src/compressors/build_log_compressor.dart packages/conatus_context/test/build_log_compressor_test.dart
git commit -m "feat(context): 增加构建日志压缩器"
```

---

### Task 11: 搜索结果压缩器

**Files:**
- Create: `packages/conatus_context/lib/src/compressors/search_results_compressor.dart`
- Test: `packages/conatus_context/test/search_results_compressor_test.dart`

**Interfaces:**
- Produces: `class SearchResultsCompressor implements ContentCompressor`，`kind => ContentKind.searchResults`

- [ ] **Step 1: 写失败测试**

测试文件顶部定义：

```dart
const CompressionBudget budget = CompressionBudget(
  maxItems: 30,
  maxLines: 10,
  maxFiles: 40,
  targetRatio: 0.5,
  retrievalId: '0123456789abcdef',
);
```

```dart
test('每文件保留首尾匹配并汇总省略数', () {
  final String input = <String>[
    for (int i = 1; i <= 100; i++) 'lib/a.dart:$i:match $i',
  ].join('\n');
  final CompressionDraft d = SearchResultsCompressor().compress(input, budget)!;
  expect(d.output, contains('lib/a.dart:1:'));
  expect(d.output, contains('lib/a.dart:100:'));
  expect(d.output, contains('more matches in lib/a.dart'));
  expect(d.unit, 'matches');
});

test('错误行优先保留', () {
  final String input = <String>[
    for (int i = 1; i <= 10; i++) 'lib/a.dart:$i:match $i',
    'lib/a.dart:11:ERROR boom',
    for (int i = 12; i <= 21; i++) 'lib/a.dart:$i:match $i',
  ].join('\n');
  final CompressionDraft d = SearchResultsCompressor().compress(input, budget)!;
  expect(d.output, contains('ERROR boom'));
});

test('文件数超过上限时按匹配数截断并汇总', () {
  final String input = <String>[
    for (int f = 0; f < 5; f++)
      for (int i = 1; i <= f + 2; i++) 'lib/f$f.dart:$i:match',
  ].join('\n');
  const CompressionBudget small = CompressionBudget(
    maxItems: 30,
    maxLines: 30,
    maxFiles: 2,
    targetRatio: 0.5,
    retrievalId: '0123456789abcdef',
  );
  final CompressionDraft d = SearchResultsCompressor().compress(input, small)!;
  expect(d.output, contains('more files with'));
});

test('ripgrep 上下文格式与 Windows 路径可解析', () {
  final String input = <String>[
    r'C:\src\pre-commit.dart-12-before',
    r'C:\src\pre-commit.dart:13:match',
    r'C:\src\pre-commit.dart-14-after',
    r'C:\src\pre-commit.dart:15:match',
  ].join('\n');
  final CompressionDraft d = SearchResultsCompressor().compress(input, budget)!;
  expect(d.output, contains(r'C:\src\pre-commit.dart:13:'));
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd packages/conatus_context && dart test test/search_results_compressor_test.dart`
Expected: FAIL。

- [ ] **Step 3: 实现**

按 spec §7.3：解析器锚定「最早出现的 `[:|-]数字[:|-]`」，路径为之前全部字符；按文件聚合；
每文件首尾 + 错误关键词行必留；文件按匹配数降序取 `maxFiles`；剩余行按行号均匀采样到
`maxLines`；回填后按原顺序输出；每文件省略提示 `[... N more matches in <path> ...]`，
被截断文件汇总 `[... N more files with M matches ...]`。

- [ ] **Step 4: 跑测试**

Run: `cd packages/conatus_context && dart test test/search_results_compressor_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_context/lib/src/compressors/search_results_compressor.dart packages/conatus_context/test/search_results_compressor_test.dart
git commit -m "feat(context): 增加搜索结果压缩器"
```

---

### Task 12: Diff 压缩器

**Files:**
- Create: `packages/conatus_context/lib/src/compressors/diff_compressor.dart`
- Test: `packages/conatus_context/test/diff_compressor_test.dart`

**Interfaces:**
- Produces: `class DiffCompressor implements ContentCompressor`，`kind => ContentKind.diff`

- [ ] **Step 1: 写失败测试**

```dart
const CompressionBudget budget = CompressionBudget(
  maxItems: 30,
  maxLines: 20,
  maxFiles: 40,
  targetRatio: 0.5,
  retrievalId: '0123456789abcdef',
);

String _manyHunks(int count) => <String>[
      'diff --git a/a b/a',
      '--- a/a',
      '+++ b/a',
      for (int i = 0; i < count; i++)
        '@@ -${i * 10 + 1},3 +${i * 10 + 1},3 @@\n context\n-old$i\n+new$i',
    ].join('\n');

test('保留全部 +/- 行，只折叠未变更上下文', () {
  final String input = 'diff --git a/a b/a\n--- a/a\n+++ b/a\n@@ -1,20 +1,20 @@\n'
      '${List<String>.generate(10, (i) => ' line$i').join('\n')}\n'
      '-old\n+new\n'
      '${List<String>.generate(10, (i) => ' tail$i').join('\n')}\n';
  final CompressionDraft d = DiffCompressor().compress(input, budget)!;
  expect(d.output, contains('-old'));
  expect(d.output, contains('+new'));
  expect(d.output, contains('context lines'));
  expect(d.unit, 'lines');
});

test('超过上限时保留首尾 hunk，中间整体省略', () {
  final String input = _manyHunks(20);
  final CompressionDraft d = DiffCompressor().compress(input, budget)!;
  expect(d.output, contains('hunks omitted'));
  expect(d.output, contains('@@ -1,'));
  expect(d.output, contains('@@ -191,'));
});

test('空 diff 或非 diff 返回 null', () {
  expect(DiffCompressor().compress('', budget), isNull);
  expect(DiffCompressor().compress('hello', budget), isNull);
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd packages/conatus_context && dart test test/diff_compressor_test.dart`
Expected: FAIL。

- [ ] **Step 3: 实现**

按 spec §7.4：逐行状态机；文件头 / hunk 头 / `+` / `-` / `\ No newline` 全保留；
上下文每侧最多 1 行，连续上下文折叠为 `[... N context lines ...]`；超 `maxLines` 时按文件
保留首尾 hunk，中间 hunk 替换为 `[... N hunks omitted ...]`；省略总数写入 `itemsOmitted`，
`unit = 'lines'`。

- [ ] **Step 4: 跑测试**

Run: `cd packages/conatus_context && dart test test/diff_compressor_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_context/lib/src/compressors/diff_compressor.dart packages/conatus_context/test/diff_compressor_test.dart
git commit -m "feat(context): 增加 diff 压缩器"
```

---

### Task 13: 表格压缩器

**Files:**
- Create: `packages/conatus_context/lib/src/compressors/tabular_compressor.dart`
- Test: `packages/conatus_context/test/tabular_compressor_test.dart`

**Interfaces:**
- Produces: `class TabularCompressor implements ContentCompressor`，`kind => ContentKind.tabular`

- [ ] **Step 1: 写失败测试**

```dart
const CompressionBudget budget = CompressionBudget(
  maxItems: 30,
  maxLines: 30,
  maxFiles: 40,
  targetRatio: 0.5,
  retrievalId: '0123456789abcdef',
);

test('CSV 保留表头、首尾行并插入省略行', () {
  final String input = 'id,name\n'
      '${List<String>.generate(100, (i) => '$i,n$i').join('\n')}';
  final CompressionDraft d = TabularCompressor().compress(input, budget)!;
  expect(d.output.split('\n').first, 'id,name');
  expect(d.output, contains('0,n0'));
  expect(d.output, contains('99,n99'));
  expect(d.output, contains('rows omitted'));
  expect(d.unit, 'rows');
});

test('markdown 表格保留分隔行', () {
  final String input = '| id | name |\n'
      '|---|---|\n'
      '${List<String>.generate(60, (i) => '| $i | n$i |').join('\n')}';
  final CompressionDraft d = TabularCompressor().compress(input, budget)!;
  expect(d.output, contains('|---|---|'));
  expect(d.output, contains('| 0 | n0 |'));
  expect(d.output, contains('| 59 | n59 |'));
});

test('列数不一致时返回 null（不误判）', () {
  expect(TabularCompressor().compress('a,b\nc\n', budget), isNull);
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd packages/conatus_context && dart test test/tabular_compressor_test.dart`
Expected: FAIL。

- [ ] **Step 3: 实现**

按 spec §7.5：分隔符 `,` / `\t` / `;` 由首个非空行判定，后续列数一致率 ≥ 90% 才处理；
保留表头 + 前 5 + 后 5 + 等距采样；行按原始文本输出，不做引号重写；markdown 表格额外保留
`|---|` 行；省略行用与表头相同列数的 `[... N rows omitted ...]`。
不实现带引号字段的 CSV 解析，文档注明。

- [ ] **Step 4: 跑测试**

Run: `cd packages/conatus_context && dart test test/tabular_compressor_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_context/lib/src/compressors/tabular_compressor.dart packages/conatus_context/test/tabular_compressor_test.dart
git commit -m "feat(context): 增加表格压缩器"
```

---

### Task 14: 文本压缩器与默认压缩器集合

**Files:**
- Create: `packages/conatus_context/lib/src/compressors/text_compressor.dart`
- Create: `packages/conatus_context/lib/src/default_compressors.dart`
- Modify: `packages/conatus_context/lib/src/context_router.dart`（默认压缩器集合）
- Test: `packages/conatus_context/test/text_compressor_test.dart`
- Test: `packages/conatus_context/test/default_compressors_test.dart`

**Interfaces:**
- Produces: `class TextCompressor implements ContentCompressor`，`kind => ContentKind.text`
- Produces: `List<ContentCompressor> defaultContentCompressors()`
- 修改 `ContextRouter` 构造：`compressors` 缺省用 `defaultContentCompressors()`

- [ ] **Step 1: 写失败测试**

```dart
const CompressionBudget budget = CompressionBudget(
  maxItems: 30,
  maxLines: 200,
  maxFiles: 40,
  targetRatio: 0.5,
  retrievalId: '0123456789abcdef',
);

test('连续重复行折叠并标注次数', () {
  final String input = List<String>.filled(200, 'same line').join('\n');
  final CompressionDraft d = TextCompressor().compress(input, budget)!;
  expect(d.output, contains('same line  (×200)'));
});

test('UUID / 路径 / URL 行必须保留', () {
  final String input = '${List<String>.filled(200, 'filler\n').join()}'
      'id=550e8400-e29b-41d4-a716-446655440000\n'
      'path=/Users/x/project/lib/main.dart\n'
      'url=https://example.com/a\n';
  final CompressionDraft d = TextCompressor().compress(input, budget)!;
  expect(d.output, contains('550e8400'));
  expect(d.output, contains('/Users/x/project/lib/main.dart'));
  expect(d.output, contains('https://example.com/a'));
});

test('收益不足返回 null', () {
  final String input = List<String>.generate(
      20, (i) => 'path=/tmp/project/file$i.dart').join('\n');
  expect(TextCompressor().compress(input, budget), isNull);
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd packages/conatus_context && dart test test/text_compressor_test.dart`
Expected: FAIL。

- [ ] **Step 3: 实现**

按 spec §7.6：连续重复行折叠为 `line  (×N)`；≥3 连续空行折叠为 1；含 UUID（`[0-9a-f]{8}-...`）、
≥8 位 hex、URL、路径、错误关键词的行必留；其余按 `targetRatio` 等距采样，头尾各 10 行；
若最终长度 > `input.length * (1 - 0.15)` → `null`。
`defaultContentCompressors()` 返回 JSON / 日志 / 搜索 / diff / 表格 / 文本六个实例。

- [ ] **Step 4: 跑测试 + 全包测试**

Run: `cd packages/conatus_context && dart test`
Expected: 全部 PASS（含此前各任务）。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_context/lib/src/compressors/text_compressor.dart packages/conatus_context/lib/src/default_compressors.dart packages/conatus_context/lib/src/context_router.dart packages/conatus_context/test/text_compressor_test.dart packages/conatus_context/test/default_compressors_test.dart
git commit -m "feat(context): 增加文本压缩器并接入默认集合"
```

---

### Task 15: 仓库接入与 Agent Loop 集成测试

**Files:**
- Modify: `pubspec.yaml`（`dependencies` 增加 `conatus_context`）
- Modify: `lib/conatus.dart`（export + 数量注释）
- Create: `test/integration/context_compression_test.dart`
- Test: 同上

**Interfaces:**
- Consumes: `provideContextCompression`、`checkModelVisibleInvariant`、`TestHarness`

- [ ] **Step 1: 写失败测试**

文件头导入：

```dart
import 'dart:convert';
import 'package:conatus/conatus.dart';
import 'package:test/test.dart';
import 'helpers/scripted_llm.dart';
import 'helpers/test_harness.dart';
```

```dart
class _BigJsonTool extends Tool {
  @override
  String get name => 'big_json';
  @override
  String get description => '返回大 JSON';
  @override
  Future<ToolResult> call(ToolContext context) async => ToolResult.success(
        jsonEncode(<Map<String, Object?>>[
          for (int i = 0; i < 300; i++)
            <String, Object?>{'id': i, 'status': i == 7 ? 500 : 200},
        ]),
      );
}

test('大 JSON 工具结果在进入模型前被压缩，且不变式成立', () async {
  final TestHarness harness = await TestHarness.create(
    llmScript: <LlmResult>[
      callTool('c1', 'big_json'),
      text('done'),
    ],
    configure: (Context app, Session session) {
      app.effect(() => app.tools.register(_BigJsonTool()));
      provideSessionLogRecorder(app);
      provideContextCompression(app,
          config: const ContextCompressionConfig(minChars: 100));
    },
  );

  await harness.run('跑一下');

  final String toolMessage = harness.llm.requests.last
      .firstWhere((LlmMessage m) => m.role == 'tool')
      .content;
  expect(toolMessage, contains('<<ctx:'));
  expect(toolMessage.length, lessThan(5000));

  final SessionLog log = harness.app.require<SessionLog>('sessionLog');
  await harness.settle();
  final List<SessionEvent> events = <SessionEvent>[];
  await log.replay(harness.session.id, events.add);
  expect(checkModelVisibleInvariant(events), isEmpty);

  final String id = parseCcrMarker(toolMessage)!.id;
  final ToolResult retrieved = await harness.app.tools.call(
      ToolCall(name: 'context_retrieve', arguments: <String, Object?>{'id': id}));
  expect(retrieved.content, contains('"id":0'));
  expect(jsonDecode(retrieved.content), isA<List<dynamic>>());
});
```

`_BigJsonTool` 直接定义在测试文件内（上方代码块），无需额外文件。

- [ ] **Step 2: 运行确认失败**

Run: `dart test test/integration/context_compression_test.dart`
Expected: 编译失败（伞包未导出 `provideContextCompression`）。

- [ ] **Step 3: 接入伞包**

- 根 `pubspec.yaml` 在 `conatus_compaction` 与 `conatus_core` 之间插入：
  `conatus_context: {path: packages/conatus_context}`
- `lib/conatus.dart` 在对应位置 `export 'package:conatus_context/conatus_context.dart';`
- 同步文件头「23 个模块包（14 稳定 + 9 实验性）」为 24 / 10。

- [ ] **Step 4: 跑集成测试与全包测试**

Run:
```bash
dart pub get
dart test test/integration/context_compression_test.dart
cd packages/conatus_context && dart test
```
Expected: PASS，不变式返回空列表。

- [ ] **Step 5: 提交**

```bash
git add pubspec.yaml lib/conatus.dart test/integration/context_compression_test.dart
git commit -m "feat(context): 接入伞包并验证 Agent Loop 不变式"
```

---

### Task 16: 文档、质量回归与收尾

**Files:**
- Create: `packages/conatus_context/README.md`
- Create: `packages/conatus_context/test/quality_test.dart`
- Modify: `README.md`（包表格）
- Modify: `AGENTS.md`（包清单与数量）
- Modify: `packages/conatus_context/lib/conatus_context.dart`（最终导出）

- [ ] **Step 1: 写质量回归测试**

在 `test/quality_test.dart` 内置六组固定样本（不读磁盘）：JSON 200 项、pytest 800 行、
grep 60 文件、diff 12 文件、CSV 500 行、散文 400 行。用同一张表驱动：

```dart
const CompressionBudget budget = CompressionBudget(
  maxItems: 30,
  maxLines: 200,
  maxFiles: 40,
  targetRatio: 0.5,
  retrievalId: '0123456789abcdef',
);

class _QualityCase {
  const _QualityCase(this.kind, this.compressor, this.input, this.mustKeep);
  final ContentKind kind;
  final ContentCompressor compressor;
  final String input;
  final String mustKeep;
}

final List<_QualityCase> cases = <_QualityCase>[
  _QualityCase(ContentKind.jsonArray, JsonArrayCompressor(), jsonSample, '"status":500'),
  _QualityCase(ContentKind.buildLog, BuildLogCompressor(), logSample, 'ERROR'),
  _QualityCase(ContentKind.searchResults, SearchResultsCompressor(), grepSample, 'lib/a.dart:100:'),
  _QualityCase(ContentKind.diff, DiffCompressor(), diffSample, '+new'),
  _QualityCase(ContentKind.tabular, TabularCompressor(), csvSample, 'id,name'),
  _QualityCase(ContentKind.text, TextCompressor(), proseSample, '550e8400'),
];

for (final _QualityCase c in cases) {
  test('${c.kind.name} 压缩后关键事实存活', () {
    final CompressionDraft? draft = c.compressor.compress(c.input, budget);
    expect(draft, isNotNull);
    expect(draft!.output.length, lessThan(c.input.length * 0.85));
    expect(draft.output, contains(c.mustKeep));
  });
}
```

断言每类：

```dart
expect(draft, isNotNull);
expect(draft!.output.length, lessThan(input.length * 0.85));
expect(draft.output, contains(必存片段));
```

必存片段：JSON 的错误项 id、pytest 的 `ERROR` 行、grep 的首尾匹配、diff 的 `+new`、
CSV 的表头、散文的 UUID。

- [ ] **Step 2: 跑质量测试**

Run: `cd packages/conatus_context && dart test test/quality_test.dart`
Expected: PASS。任一失败先修压缩器，不放宽断言。

- [ ] **Step 3: 写包 README**

必须包含：定位与边界（与 `layered-compaction` / `tool-result-eviction` 的分工与建议注册顺序）、
快速开始（内存与文件两种装配）、六类压缩器与保留规则表、CCR 标记协议与两个工具、
配置表（逐项默认值）、失败与降级行为、已知限制（CSV 引号字段、源码透传、token 为估算）、
许可证与思路来源（headroomlabs-ai/headroom，Apache-2.0，独立实现）。

- [ ] **Step 4: 更新根文档**

- `README.md` 实验性包表格增加 `conatus_context` 行（依赖 `conatus_core`、`conatus_foundation`、`conatus_llm`）。
- `AGENTS.md`：实验性包计数 `×9` → `×10`，包表格增加一行；若正文出现「23 个模块包」同步为 24。
- `lib/conatus.dart` / 根 `pubspec.yaml` 的包数量描述同步为 24（14 稳定 + 10 实验性）。

最终 `lib/conatus_context.dart` 至少导出：

```dart
export 'src/ccr_file_store.dart' show CcrFileStore, contextCacheDir;
export 'src/ccr_marker.dart'
    show
        CcrMarker,
        ccrIdOf,
        containsCcrMarker,
        encodeCcrMarker,
        kCcrMarkerPrefix,
        parseCcrMarker;
export 'src/ccr_memory_store.dart' show CcrMemoryStore;
export 'src/ccr_store.dart' show CcrEntry, CcrStore;
export 'src/compress_messages.dart' show compressMessages;
export 'src/compression_result.dart' show ContextCompressionResult;
export 'src/compression_stats.dart' show CompressionStats, KindStats;
export 'src/compressors/json_array_compressor.dart' show JsonArrayCompressor;
export 'src/compressors/build_log_compressor.dart' show BuildLogCompressor;
export 'src/compressors/search_results_compressor.dart' show SearchResultsCompressor;
export 'src/compressors/diff_compressor.dart' show DiffCompressor;
export 'src/compressors/tabular_compressor.dart' show TabularCompressor;
export 'src/compressors/text_compressor.dart' show TextCompressor;
export 'src/content_compressor.dart'
    show CompressionBudget, CompressionDraft, ContentCompressor;
export 'src/content_detector.dart' show ContentDetection, Detector, detectContent;
export 'src/content_kind.dart' show ContentKind;
export 'src/context_compression_config.dart' show ContextCompressionConfig;
export 'src/context_retrieval_tool.dart' show ContextRetrievalTool;
export 'src/context_router.dart' show ContextRouter;
export 'src/context_stats_tool.dart' show ContextStatsTool;
export 'src/default_compressors.dart' show defaultContentCompressors;
export 'src/provide_context_compression.dart'
    show
        ContextCompressionContext,
        ContextCompressionService,
        provideContextCompression;
```

- [ ] **Step 5: 全量验证**

Run:
```bash
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
for d in packages/*/; do (cd "$d" && dart test) || exit 1; done
bash tool/version.sh
```
Expected: 全部通过；`version.sh` 输出冻结校验通过。

- [ ] **Step 6: 提交并推送**

```bash
git add packages/conatus_context README.md AGENTS.md lib/conatus.dart pubspec.yaml
git commit -m "docs(context): 补充 conatus_context 文档与质量回归"
git push
```

---

## 完成标准

- `conatus_context` 在伞包中可 `import 'package:conatus/conatus.dart';` 直接使用。
- 六类压缩器均有金样与保真测试；Router 的安全门、fail-open、幂等、确定性均有测试。
- 内存与文件两种 CCR 后端都通过往返、TTL、LRU、篡改校验测试。
- Agent Loop 集成测试证明：模型看到压缩版、日志可重建、`context_retrieve` 能取回原文。
- `dart analyze --fatal-infos`、全仓测试、`tool/version.sh` 全绿。
