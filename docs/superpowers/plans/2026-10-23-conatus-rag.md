# conatus_rag 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新建稳定包 `conatus_rag`：把会话历史切块、嵌入、按租户/权限检索，并以 `rag_search` 工具和可选 `EvidenceSource` 钩子接入 Agent，全程不增加 `conatus_agent` 的依赖。

**Architecture:** 摄取侧用 `SessionLog.read` + 游标增量拉事件，`Chunker` 保留 citation，`Embedder` 批量生成向量后写入 `RagIndexBackend`。检索侧由 `DenseRetriever` 做「嵌入 → 后端按 filter 搜索 → 重排 → token 预算」，`VisibilityPolicy` 在检索前下推 `RagFilter`、检索后复核。`RagService` 组合这些部件并提供 `provideRag`；agent 只新增通用 `EvidenceSource` 函数钩子，rag 包与 agent 互不依赖。

**Tech Stack:** Dart 3.6+、`package:http`（OpenAI 兼容 `/embeddings` 与 `/rerank`）、`package:test`、仓库现有 `conatus_core` / `conatus_foundation`（Session / SessionLog / Tools / Logger）。

**Spec:** `docs/superpowers/specs/2026-10-23-conatus-raw-rag-design.md`

## Global Constraints

- 新包 `packages/conatus_rag`：`version: 0.16.0`、`publish_to: none`、`resolution: workspace`、`sdk: ^3.6.0`。
- 依赖只允许：`conatus_core`、`conatus_foundation`、`http: ^1.2.0`；dev 只允许 `lints: ^4.0.0`、`test: ^1.25.0`。
- **`conatus_agent` 的 pubspec 与源码不得出现 `conatus_rag`**；agent 只新增 `EvidenceSource` 函数类型。
- 单文件 ≤ 200 行、单 class ≤ 150 行、函数体 ≤ 40 行、函数参数 ≤ 4 个（超出用配置对象）。
- 每个函数内 `if/else/switch/case` 总数 ≤ 3、嵌套 ≤ 2、单个条件连续 `&&/||` ≤ 2；禁止嵌套三元；优先 early return。
- 布尔变量/函数用状态词，禁止 `is/has/can/should` 前缀；函数名「动词 + 名词」。
- 包内用相对导入；单引号；`prefer_final_locals`；`const` 优先；`directives_ordering`。
- 不把 apiKey、query 原文、证据正文写进日志/异常消息。
- 所有测试离线：HTTP 用注入的 `http.Client`（`package:http/testing.dart` 的 `MockClient`），不访问网络。
- 提交信息：`feat(rag): ...` / `test(rag): ...` / `docs(rag): ...`，中文描述。
- 收尾命令：根目录 `dart pub get && dart analyze --fatal-infos && dart format .`，并跑受影响包测试。
- rag 测试统一用 `packages/conatus_rag/test/helpers/fixtures.dart` 的 `chunk(...)`（Task 4 创建）；下文测试片段默认已 import 该文件与 `package:test/test.dart`。
- 各测试文件自带微型替身（不跨文件 import）：`_Embedder`（`model == 'fake'`、`dimension == 2`、恒返回 `<double>[1, 0]`）、`_ThrowingEmbedder`（`embedBatch` 抛 `StateError`）、`_ThrowingReranker`（`rerank` 抛 `StateError`）。

## Review Focus

最可能被真实输入击穿、且规格没有逐条列出的五类行为（每类在括注任务里有对应测试）：

1. **同进程跨租户**：同一后端实例、同一 `sessionId` 命名空间下，租户 B 不能通过检索或工具拿到租户 A 的块。（Task 8、Task 12）
2. **空/缺失 `visibilityTags`**：IdP 未同步时不得退化成「全库可见」，必须 fail closed 返回空。（Task 8）
3. **嵌入端点返回坏数据**：维度不符或空数组时，不得写入半截向量，也不得推进游标。（Task 6、Task 8）
4. **超长单条工具输出**：必须按 `maxChunkChars` 截断且保留 citation，不能让单块撑爆上下文。（Task 3）
5. **索引文件损坏**：JSON 反序列化失败必须抛 `rag_backend_broken`，不得静默当作空索引（那会掩盖数据丢失）。（Task 5）

---

### Task 1: 包骨架与类型词汇

**Files:**
- Create: `packages/conatus_rag/pubspec.yaml`
- Create: `packages/conatus_rag/analysis_options.yaml`
- Create: `packages/conatus_rag/lib/conatus_rag.dart`
- Create: `packages/conatus_rag/lib/src/rag_types.dart`
- Create: `packages/conatus_rag/test/rag_types_test.dart`
- Create: `packages/conatus_rag/README.md`
- Create: `packages/conatus_rag/CHANGELOG.md`

**Interfaces:**
- Produces: `RagScope`, `RagSource`, `RagChunk`, `Citation`, `RagHit`, `RetrievalRequest`, `RagFilter`, `RagStats`, `RagException`, `RagCursor`, `RagSnapshotMeta`, `RagSnapshot`, `ChunkerConfig`, `estimateTokens(String) -> int`。

- [ ] **Step 1: 建包骨架**

`pubspec.yaml` 按 Global Constraints 写；`analysis_options.yaml` 只写 `include: ../../analysis_options.yaml`。
`lib/conatus_rag.dart` 先只有 library 文档与 `export 'src/rag_types.dart';`。
`README.md` / `CHANGELOG.md` 先写标题与一句定位（Task 14 补全）。

- [ ] **Step 2: 写失败测试**

```dart
// test/rag_types_test.dart
import 'package:conatus_rag/conatus_rag.dart';
import 'package:test/test.dart';

void main() {
  test('RagScope 自动补租户标签并拒绝空租户', () {
    final RagScope scope = RagScope(
        tenantId: 't1', principalId: 'u1', visibilityTags: {'dept:fin'});
    expect(scope.visibilityTags, containsAll(<String>['tenant:t1', 'dept:fin']));
    expect(() => RagScope(tenantId: '  '), throwsArgumentError);
  });

  test('RagChunk JSON 往返保留 citation 与时间', () {
    final RagChunk chunk = RagChunk(
      id: 'session/s1/0-3', tenantId: 't1', sourceKind: 'session',
      sourceId: 's1', firstSeq: 0, lastSeq: 3, eventIds: {'e1', 'e2'},
      startTime: DateTime.utc(2026, 10, 20, 14, 3),
      endTime: DateTime.utc(2026, 10, 20, 14, 9),
      text: '用户：你好',
    );
    final RagChunk back = RagChunk.fromJson(chunk.toJson());
    expect(back.citation.sourceId, 's1');
    expect(back.citation.firstSeq, 0);
    expect(back.startTime, DateTime.utc(2026, 10, 20, 14, 3));
    expect(back.eventIds, <String>{'e1', 'e2'});
  });

  test('estimateTokens 对空串为 0、对中文按 2 字 1 token 保守估计', () {
    expect(estimateTokens(''), 0);
    expect(estimateTokens('一二三四'), 2);
  });

  test('RagStats.zero 全为 0，RagException 带错误码', () {
    expect(RagStats.zero().retrievals, 0);
    expect(const RagException('rag_x', '坏了').toString(), contains('rag_x'));
  });
}
```

- [ ] **Step 3: 运行确认失败**

Run: `cd packages/conatus_rag && dart pub get && dart test test/rag_types_test.dart`
Expected: FAIL（`RagScope` 等未定义）。

- [ ] **Step 4: 实现类型**

`rag_types.dart` 定义：
- `RagScope`：构造期校验非空 `tenantId`，并把 `tenant:<tenantId>` 并入 `visibilityTags`。
- `RagChunk`：字段与 spec §5 一致；`toJson` / `fromJson`；`Citation get citation`。
- `RagSource {sourceKind, sourceId, scope}`；`ChunkerConfig {chunkChars, overlapChars, maxChunkChars}`。
- `RagHit {chunk, score, rerankScore}`。
- `RetrievalRequest {query, scope, limit, tokenBudget, sourceIds, from, to}`，缺省 `limit: 15`、`tokenBudget: 2000`。
- `RagFilter {tenantId, anyTags, sourceIds, from, to}`。
- `RagCursor {tenantId, sourceId, lastSeq}`（JSON 往返）。
- `RagSnapshotMeta {embeddingModel, dimension, indexVersion, updatedAt}`，`bool matches(...)`。
- `RagSnapshot {meta, chunks, vectors, cursors}`。
- `RagStats`：`final int chunks, retrievals, emptyResults, rerankFallbacks, embedFailures; final DateTime? lastIngestAt;` + `RagStats.zero()`。
- `RagException {code, message}`。
- `int estimateTokens(String text)`：`(text.runes.length / 2).ceil()`，空串 0。

- [ ] **Step 5: 运行确认通过**

Run: `cd packages/conatus_rag && dart test test/rag_types_test.dart && dart analyze`
Expected: PASS，analyze 无 issue。

- [ ] **Step 6: 提交**

```bash
git add packages/conatus_rag
git commit -m "feat(rag): 新建 conatus_rag 包与核心类型"
```

---

### Task 2: 余弦与向量索引

**Files:**
- Create: `packages/conatus_rag/lib/src/cosine.dart`
- Create: `packages/conatus_rag/lib/src/vector_index.dart`
- Create: `packages/conatus_rag/test/vector_index_test.dart`
- Modify: `packages/conatus_rag/lib/conatus_rag.dart`（export 两文件）

**Interfaces:**
- Produces: `double cosineSimilarity(List<double> a, List<double> b)`；`VectorIndex`、`VectorMatch {id, score}`。

- [ ] **Step 1: 写失败测试**

```dart
test('向量索引按余弦排序、截断 k、支持删除', () {
  final VectorIndex index = VectorIndex(dimension: 2);
  index.upsert('a', <double>[1, 0]);
  index.upsert('b', <double>[0, 1]);
  index.upsert('c', <double>[0.9, 0.1]);
  expect(index.search(<double>[1, 0], 2).map((VectorMatch m) => m.id),
      <String>['a', 'c']);
  index.remove('a');
  expect(index.length, 2);
  expect(index.search(<double>[1, 0], 5), hasLength(2));
});

test('余弦与维度校验', () {
  expect(cosineSimilarity(<double>[1, 0], <double>[0, 1]), 0);
  expect(cosineSimilarity(<double>[0, 0], <double>[1, 0]), 0);
  expect(() => cosineSimilarity(<double>[1], <double>[1, 2]), throwsArgumentError);
  expect(() => VectorIndex(dimension: 2).upsert('x', <double>[1]), throwsArgumentError);
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd packages/conatus_rag && dart test test/vector_index_test.dart`
Expected: FAIL（未定义）。

- [ ] **Step 3: 实现**

`cosine.dart`：逐元素点积/范数，零向量返回 `0.0`，维度不等抛 `ArgumentError`。
`vector_index.dart`：`Map<String, List<double>>`；`upsert` 校验维度；`search` 逐条算分、降序、取 `k`；`remove`、`length`。

- [ ] **Step 4: 运行确认通过**

Run: `cd packages/conatus_rag && dart test test/vector_index_test.dart && dart analyze`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_rag
git commit -m "feat(rag): 余弦与平坦向量索引"
```

---

### Task 3: 会话切块与 citation

**Files:**
- Create: `packages/conatus_rag/lib/src/chunker.dart`
- Create: `packages/conatus_rag/test/chunker_test.dart`
- Modify: `packages/conatus_rag/lib/conatus_rag.dart`

**Interfaces:**
- Consumes: `RagSource`、`ChunkerConfig`、`SessionEvent`（`conatus_foundation`）。
- Produces: `List<RagChunk> chunkEvents(RagSource source, Iterable<SessionEvent> events, ChunkerConfig config)`；`String eventText(SessionEvent event)`（未知/被过滤事件返回空串）。

- [ ] **Step 1: 写失败测试**

```dart
SessionEvent ev(int seq, String type, Map<String, Object?> data) => SessionEvent(
      seq: seq, type: type, time: DateTime.utc(2026, 10, 20, 14, seq),
      data: data, id: 'e$seq', sessionId: 's1');

void main() {
  final RagSource source = RagSource(
      sourceKind: 'session', sourceId: 's1',
      scope: RagScope(tenantId: 't1', visibilityTags: {'dept:fin'}));

  test('只索引白名单事件，保留 seq/时间/事件 id', () {
    final List<RagChunk> chunks = chunkEvents(source, <SessionEvent>[
      ev(0, kUserMessageEvent, <String, Object?>{'text': '我喜欢京剧'}),
      ev(1, kAssistantMessageEvent, <String, Object?>{'text': '记住了'}),
      ev(2, 'llm/request', <String, Object?>{'text': '不该出现'}),
    ], const ChunkerConfig(chunkChars: 200, overlapChars: 20, maxChunkChars: 300));
    expect(chunks, hasLength(1));
    expect(chunks.single.firstSeq, 0);
    expect(chunks.single.lastSeq, 1);
    expect(chunks.single.eventIds, <String>{'e0', 'e1'});
    expect(chunks.single.text, contains('京剧'));
    expect(chunks.single.text, isNot(contains('不该出现')));
    expect(chunks.single.tenantId, 't1');
  });

  test('超长工具输出按 maxChunkChars 截断并保留来源', () {
    final String huge = 'x' * 500;
    final List<RagChunk> chunks = chunkEvents(source, <SessionEvent>[
      ev(0, kToolResultEvent,
          <String, Object?>{'name': 'read', 'content': huge}),
    ], const ChunkerConfig(chunkChars: 2000, overlapChars: 20, maxChunkChars: 40));
    expect(chunks.single.text.length, lessThanOrEqualTo(80));
    expect(chunks.single.text, contains('…[截断]'));
    expect(chunks.single.citation.sourceId, 's1');
  });

  test('长会话切多块、块 id 稳定可复现', () {
    final List<SessionEvent> events = <SessionEvent>[
      for (int i = 0; i < 6; i++)
        ev(i, kUserMessageEvent, <String, Object?>{'text': '第$i条消息内容'}),
    ];
    const ChunkerConfig config =
        ChunkerConfig(chunkChars: 40, overlapChars: 8, maxChunkChars: 100);
    final List<RagChunk> first = chunkEvents(source, events, config);
    final List<RagChunk> second = chunkEvents(source, events, config);
    expect(first.length, greaterThan(1));
    expect(first.map((RagChunk c) => c.id), second.map((RagChunk c) => c.id));
    expect(first.map((RagChunk c) => c.id).toSet(), hasLength(first.length));
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd packages/conatus_rag && dart test test/chunker_test.dart`
Expected: FAIL。

- [ ] **Step 3: 实现**

- `eventText`：`user/message` → `用户：<text>`；`assistant/message` → `助手：<text>`；`tool/call` → `工具调用 <name>(<json args>)`；`tool/result` → `工具结果 <name>：<content>`；其余返回 `''`。
- 每行先按 `maxChunkChars` 截断并追加 `…[截断]`。
- 建 `_Line {event, start, end}`，拼成整串后按 `chunkChars` 滑窗、步长 `chunkChars - overlapChars`。
- 每块：`id = '<sourceKind>/<sourceId>/<firstSeq>-<lastSeq>-<windowIndex>'`（窗口序号必须入 id：同一组事件可能被重叠窗切成多块，只用 seq 区间会互相覆盖）；`eventIds` 取与窗口相交的行；时间取相交行的 min/max；跳过没有相交行的窗口。
- 不合并空行；正文保持原文（除截断）。

- [ ] **Step 4: 运行确认通过**

Run: `cd packages/conatus_rag && dart test test/chunker_test.dart && dart analyze`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_rag
git commit -m "feat(rag): 会话切块与 citation 保留"
```

---

### Task 4: 后端端口与内存实现

**Files:**
- Create: `packages/conatus_rag/lib/src/rag_backend.dart`
- Create: `packages/conatus_rag/test/helpers/fixtures.dart`（共享 `chunk(...)` 构造，后续所有 rag 测试复用）
- Create: `packages/conatus_rag/test/in_memory_backend_test.dart`
- Modify: `packages/conatus_rag/lib/conatus_rag.dart`

**Interfaces:**
- Consumes: Task 1/2 的类型。
- Produces:
  - `abstract interface class RagIndexBackend`（spec §5 全部方法）
  - `class InMemoryRagBackend implements RagIndexBackend`
  - `bool chunkMatches(RagChunk chunk, RagFilter filter)`（顶层，供 JSON 后端复用）
  - 测试夹具 `RagChunk chunk(String id, String tenant, Set<String> tags, int seq, {String? text, DateTime? time})`

- [ ] **Step 1: 写失败测试**

`test/helpers/fixtures.dart`：

```dart
import 'package:conatus_rag/conatus_rag.dart';

RagChunk chunk(String id, String tenant, Set<String> tags, int seq,
        {String? text, DateTime? time}) =>
    RagChunk(
      id: id, tenantId: tenant, sourceKind: 'session', sourceId: 's$seq',
      firstSeq: seq, lastSeq: seq, eventIds: <String>{'e$seq'},
      startTime: time ?? DateTime.utc(2026, 10, 20),
      endTime: time ?? DateTime.utc(2026, 10, 20),
      text: text ?? '正文$id', visibilityTags: tags,
    );
```

`test/in_memory_backend_test.dart`（import `helpers/fixtures.dart`）：

void main() {
  late InMemoryRagBackend backend;
  setUp(() => backend = InMemoryRagBackend());

  test('按租户与标签过滤，跨租户不可见', () async {
    await backend.upsert(<RagChunk>[
      chunk('a', 't1', <String>{'tenant:t1', 'dept:fin'}, 0),
      chunk('b', 't2', <String>{'tenant:t2'}, 1),
    ], <List<double>>[
      <double>[1, 0], <double>[1, 0],
    ]);
    final RagScope scope = RagScope(tenantId: 't1', visibilityTags: {'dept:fin'});
    final List<RagHit> hits = await backend.search(
      RagFilter(tenantId: 't1', anyTags: scope.visibilityTags),
      queryVector: <double>[1, 0], k: 10);
    expect(hits.map((RagHit h) => h.chunk.id), <String>['a']);
  });

  test('空标签与时间窗过滤', () async {
    await backend.upsert(<RagChunk>[
      chunk('a', 't1', <String>{'tenant:t1'}, 0, time: DateTime.utc(2026, 1, 1)),
    ], <List<double>>[<double>[1, 0]]);
    expect(await backend.search(
      RagFilter(tenantId: 't1', anyTags: const <String>{}),
      queryVector: <double>[1, 0], k: 10), isEmpty);
    expect(await backend.search(
      RagFilter(tenantId: 't1', anyTags: {'tenant:t1'},
          from: DateTime.utc(2026, 6, 1)),
      queryVector: <double>[1, 0], k: 10), isEmpty);
  });

  test('meta、游标、delete 连带清游标、count', () async {
    const RagSnapshotMeta meta = RagSnapshotMeta(
        embeddingModel: 'e', dimension: 2, indexVersion: 1);
    await backend.init(meta);
    await backend.init(meta);
    expect((await backend.meta())!.embeddingModel, 'e');
    expect(() => backend.init(const RagSnapshotMeta(
        embeddingModel: 'other', dimension: 2, indexVersion: 1)),
        throwsA(isA<RagException>()));
    await backend.upsert(<RagChunk>[chunk('a', 't1', {'tenant:t1'}, 0)],
        <List<double>>[<double>[1, 0]]);
    await backend.saveCursor(const RagCursor(
        tenantId: 't1', sourceId: 's0', lastSeq: 0));
    expect(await backend.count(), 1);
    expect(await backend.delete(
        RagFilter(tenantId: 't1', sourceIds: <String>{'s0'})), 1);
    expect(await backend.count(), 0);
    expect(await backend.cursorOf('s0'), isNull);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd packages/conatus_rag && dart test test/in_memory_backend_test.dart`
Expected: FAIL。

- [ ] **Step 3: 实现**

- `chunkMatches`：`tenantId` 相等 → `anyTags` 为 null 放行、为空集则拒绝、否则交集非空 → `sourceIds` 包含 → 时间窗与 `[startTime,endTime]` 相交。
- `InMemoryRagBackend`：`_chunks`、`_vectors`、`_cursors`、`_meta`；`search` 用 `VectorIndex`，按 filter 过滤后取 `k`；`delete` 删除匹配块并清掉匹配 `sourceIds`（或同租户）的游标；`init` 在 meta 不一致时抛 `RagException('rag_index_stale', ...)`。
- `upsert` 校验 `chunks.length == vectors.length`，否则 `ArgumentError`。

- [ ] **Step 4: 运行确认通过**

Run: `cd packages/conatus_rag && dart test test/in_memory_backend_test.dart && dart analyze`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_rag
git commit -m "feat(rag): 索引后端端口与内存实现"
```

---

### Task 5: JSON 后端（原子写、损坏 fail closed）

**Files:**
- Create: `packages/conatus_rag/lib/src/json_backend.dart`
- Create: `packages/conatus_rag/test/json_backend_test.dart`
- Modify: `packages/conatus_rag/lib/conatus_rag.dart`
- Modify: `packages/conatus_rag/lib/src/rag_backend.dart`（如需露出 `RagSnapshot` 序列化辅助）

**Interfaces:**
- Produces: `class JsonRagBackend implements RagIndexBackend { JsonRagBackend({required File file}); }`

- [ ] **Step 1: 写失败测试**

```dart
test('JSON 后端跨实例往返，原子写不留临时文件', () async {
  final Directory dir = await Directory.systemTemp.createTemp('rag');
  final File file = File('${dir.path}/index.json');
  final JsonRagBackend first = JsonRagBackend(file: file);
  await first.init(const RagSnapshotMeta(
      embeddingModel: 'e', dimension: 2, indexVersion: 1));
  await first.upsert(<RagChunk>[chunk('a', 't1', {'tenant:t1'}, 0)],
      <List<double>>[<double>[1, 0]]);
  await first.saveCursor(
      const RagCursor(tenantId: 't1', sourceId: 's0', lastSeq: 0));

  final JsonRagBackend second = JsonRagBackend(file: file);
  expect(await second.count(), 1);
  expect((await second.cursorOf('s0'))!.lastSeq, 0);
  expect(file.parent.listSync().where((FileSystemEntity e) =>
      e.path.endsWith('.tmp')), isEmpty);
});

test('损坏文件抛 rag_backend_broken 而不是静默清空', () async {
  final Directory dir = await Directory.systemTemp.createTemp('rag');
  final File file = File('${dir.path}/bad.json')..writeAsStringSync('{oops');
  await expectLater(JsonRagBackend(file: file).count(),
      throwsA(isA<RagException>().having(
          (RagException e) => e.code, 'code', 'rag_backend_broken')));
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd packages/conatus_rag && dart test test/json_backend_test.dart`
Expected: FAIL。

- [ ] **Step 3: 实现**

- 组合一个 `InMemoryRagBackend` 作为内存视图；`_ensureLoaded` 首次操作时读文件。
- 反序列化：非对象/字段类型不符 → `RagException('rag_backend_broken', '索引文件损坏，需 rebuild()')`。
- 每次变更后 `_save`：写 `<file>.tmp` → `rename(file.path)`（覆盖），`flush: true`；`file.parent.create(recursive: true)`。
- 所有端口方法先 `await _ensureLoaded()`，变更后 `await _save()`。

- [ ] **Step 4: 运行确认通过**

Run: `cd packages/conatus_rag && dart test test/json_backend_test.dart && dart analyze`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_rag
git commit -m "feat(rag): JSON 索引后端（原子写、损坏 fail closed）"
```

---

### Task 6: 嵌入端点

**Files:**
- Create: `packages/conatus_rag/lib/src/embedder.dart`
- Create: `packages/conatus_rag/test/embedder_test.dart`
- Modify: `packages/conatus_rag/lib/conatus_rag.dart`

**Interfaces:**
- Produces: `abstract interface class Embedder { String get model; int get dimension; Future<List<double>> embed(String text); Future<List<List<double>>> embedBatch(List<String> texts); void dispose(); }`；`class OpenAiEmbedder implements Embedder`。

- [ ] **Step 1: 写失败测试**

```dart
MockClient okClient(List<Map<String, Object?>> seen) => MockClient((Request req) async {
      seen.add(<String, Object?>{
        'url': req.url.toString(),
        'auth': req.headers['Authorization'],
        'body': jsonDecode(req.body),
      });
      final Map<String, Object?> body = jsonDecode(req.body) as Map<String, Object?>;
      final List<Object?> input = body['input']! as List<Object?>;
      return Response(jsonEncode(<String, Object?>{
        'data': <Map<String, Object?>>[
          for (int i = 0; i < input.length; i++)
            <String, Object?>{'index': i, 'embedding': <double>[1, 0]},
        ],
      }), 200);
    });

test('OpenAI 兼容 /embeddings：鉴权、批量切分、解析', () async {
  final List<Map<String, Object?>> seen = <Map<String, Object?>>[];
  final OpenAiEmbedder embedder = OpenAiEmbedder(
    baseUrl: 'https://api.test/v3', model: 'm', apiKey: 'SECRET',
    dimension: 2, batchSize: 2, client: okClient(seen));
  final List<List<double>> vectors =
      await embedder.embedBatch(<String>['a', 'b', 'c']);
  expect(vectors, hasLength(3));
  expect(seen, hasLength(2));
  expect(seen.first['url'], 'https://api.test/v3/embeddings');
  expect(seen.first['auth'], 'Bearer SECRET');
  expect(embedder.model, 'm');
});

test('维度不符与 401 都抛 rag_embed_failed，消息不含 key', () async {
  final OpenAiEmbedder bad = OpenAiEmbedder(
    baseUrl: 'https://api.test/v3', model: 'm', apiKey: 'SECRET', dimension: 3,
    client: MockClient((Request req) async => Response(jsonEncode(
        <String, Object?>{'data': <Map<String, Object?>>[
          <String, Object?>{'index': 0, 'embedding': <double>[1, 0]},
        ]}), 200)));
  await expectLater(bad.embed('x'), throwsA(isA<RagException>()));
  final OpenAiEmbedder denied = OpenAiEmbedder(
    baseUrl: 'https://api.test/v3', model: 'm', apiKey: 'SECRET', dimension: 2,
    client: MockClient((Request req) async => Response('nope', 401)));
  try {
    await denied.embed('x');
    fail('应当抛错');
  } on RagException catch (e) {
    expect(e.code, 'rag_embed_failed');
    expect(e.message, isNot(contains('SECRET')));
  }
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd packages/conatus_rag && dart test test/embedder_test.dart`
Expected: FAIL。

- [ ] **Step 3: 实现**

- `embed` = `embedBatch([text])` 取首条。
- 请求：`POST $baseUrl/embeddings`，头 `Authorization: Bearer <key>`、`Content-Type: application/json`，体 `{model, input: <batch>}`。
- 非 2xx、JSON 解析失败、`data` 长度不符、向量维度不符 → `RagException('rag_embed_failed', ...)`（消息只含状态码/维度）。
- `dispose` 关闭注入的 client（未注入时不关，避免影响外部共享 client：用 `_ownsClient` 标记）。

- [ ] **Step 4: 运行确认通过**

Run: `cd packages/conatus_rag && dart test test/embedder_test.dart && dart analyze`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_rag
git commit -m "feat(rag): OpenAI 兼容嵌入端点"
```

---

### Task 7: 重排与 DenseRetriever

**Files:**
- Create: `packages/conatus_rag/lib/src/reranker.dart`
- Create: `packages/conatus_rag/lib/src/retriever.dart`
- Create: `packages/conatus_rag/test/retriever_test.dart`
- Modify: `packages/conatus_rag/lib/conatus_rag.dart`

**Interfaces:**
- Consumes: `Embedder`、`RagIndexBackend`、`RagHit`。
- Produces:
  - `abstract interface class Reranker { Future<List<RagHit>> rerank(String query, List<RagHit> candidates, {required int topK}); }`
  - `class NoopReranker implements Reranker`
  - `class HttpReranker implements Reranker`（`baseUrl` / `model` / `apiKey` / `client`）
  - `class DenseRetriever implements Retriever`（`embedder`、`backend`、`reranker`、`candidates=128`、`topK=15`、`tokenBudget=2000`）

- [ ] **Step 1: 写失败测试**

```dart
class _Embedder implements Embedder {
  @override String get model => 'fake';
  @override int get dimension => 2;
  @override Future<List<double>> embed(String text) async => <double>[1, 0];
  @override Future<List<List<double>>> embedBatch(List<String> texts) async =>
      <List<double>>[for (final String _ in texts) <double>[1, 0]];
  @override void dispose() {}
}

class _ReversingReranker implements Reranker {
  @override Future<List<RagHit>> rerank(String query, List<RagHit> candidates,
      {required int topK}) async {
    final List<RagHit> reversed = candidates.reversed.toList();
    return reversed.take(topK).toList();
  }
}

class _ThrowingReranker implements Reranker {
  @override Future<List<RagHit>> rerank(String query, List<RagHit> candidates,
          {required int topK}) async =>
      throw StateError('rerank 端点挂了');
}

test('重排生效、预算截断、重排失败回退余弦', () async {
  final InMemoryRagBackend backend = InMemoryRagBackend();
  await backend.upsert(<RagChunk>[
    chunk('a', 't1', <String>{'tenant:t1'}, 0, text: '一' * 100),
    chunk('b', 't1', <String>{'tenant:t1'}, 1, text: '二' * 100),
  ], <List<double>>[<double>[1, 0], <double>[0.9, 0.1]]);
  final RagScope scope = RagScope(tenantId: 't1');
  final RagFilter filter = RagFilter(tenantId: 't1', anyTags: scope.visibilityTags);
  final RetrievalRequest request = RetrievalRequest(
      query: 'q', scope: scope, tokenBudget: 60);

  final DenseRetriever retriever = DenseRetriever(
      embedder: _Embedder(), backend: backend, reranker: _ReversingReranker());
  final List<RagHit> hits = await retriever.retrieve(request, filter);
  expect(hits.first.chunk.id, 'b');
  expect(hits.every((RagHit h) => estimateTokens(h.chunk.text) <= 60), isTrue);

  final DenseRetriever broken = DenseRetriever(
      embedder: _Embedder(), backend: backend,
      reranker: _ThrowingReranker());
  final List<RagHit> fallback = await broken.retrieve(request, filter);
  expect(fallback.first.chunk.id, 'a');
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd packages/conatus_rag && dart test test/retriever_test.dart`
Expected: FAIL。

- [ ] **Step 3: 实现**

- `DenseRetriever.retrieve`：`embedder.embed(query)` → 把 `request.sourceIds/from/to` 合入 `filter` → `backend.search(effectiveFilter, queryVector: vector, k: candidates)` → `reranker?.rerank(...)`（捕获任何异常，回退原序并计数由 service 处理）→ 按 `tokenBudget` 累加截断（至少保留 1 条）→ `take(topK)`。
- 预算用 `estimateTokens`；超预算的条目跳过，总预算不再增加。
- `NoopReranker` 原样 `take(topK)`。
- `HttpReranker`：`POST $baseUrl/rerank`，体 `{model, query, documents: [text...], top_n: topK}`；解析 `results[{index, relevance_score}]`；失败抛 `RagException('rag_rerank_failed')`。

- [ ] **Step 4: 运行确认通过**

Run: `cd packages/conatus_rag && dart test test/retriever_test.dart && dart analyze`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_rag
git commit -m "feat(rag): 重排与预算内稠密检索"
```

---

### Task 8: 可见性策略与摄取编排

**Files:**
- Create: `packages/conatus_rag/lib/src/visibility.dart`
- Create: `packages/conatus_rag/lib/src/rag_index.dart`
- Create: `packages/conatus_rag/test/visibility_test.dart`
- Create: `packages/conatus_rag/test/rag_index_test.dart`
- Modify: `packages/conatus_rag/lib/conatus_rag.dart`

**Interfaces:**
- Consumes: `SessionLog`、`Chunker`、`Embedder`、`RagIndexBackend`、`ScopeResolver`。
- Produces:
  - `abstract interface class VisibilityPolicy { RagFilter filterFor(RagScope scope); bool allows(RagChunk chunk, RagScope scope); }`
  - `class TenantTagPolicy implements VisibilityPolicy`
  - `typedef ScopeResolver = Future<RagScope> Function(String sourceId);`
  - `class RagIndexer { RagIndexer({required backend, required embedder, required log, required scopeOf, required chunking, required indexVersion}); final RagIndexBackend backend; final Embedder embedder; Future<int> ingestSession(String sourceId); Future<int> ingestAll(); Future<void> ensureIngested(); Future<void> rebuild(); }`
  - 说明：`RagIndexer` 不依赖 `RagConfig`（它在 Task 9 才出现），只接收 `ChunkerConfig` 与 `indexVersion`；Task 9 的 `RagConfig` 负责把它们组装进来。

- [ ] **Step 1: 写失败测试（visibility）**

```dart
test('同租户+标签交集可见，空标签 fail closed', () {
  final TenantTagPolicy policy = TenantTagPolicy();
  final RagScope fin = RagScope(tenantId: 't1', visibilityTags: {'dept:fin'});
  expect(policy.allows(chunk('a', 't1', {'tenant:t1', 'dept:fin'}, 0), fin), isTrue);
  expect(policy.allows(chunk('b', 't1', {'tenant:t1', 'dept:hr'}, 1), fin), isFalse);
  expect(policy.allows(chunk('c', 't2', {'tenant:t2'}, 2), fin), isFalse);
  final RagScope bare = RagScope(tenantId: 't1', visibilityTags: const <String>{});
  expect(policy.filterFor(bare).anyTags, <String>{'tenant:t1'});
  expect(policy.allows(chunk('d', 't1', {'tenant:t1'}, 3), bare), isTrue);
});
```

- [ ] **Step 2: 写失败测试（indexer）**

```dart
test('重复摄取幂等，新事件增量，失败不推进游标', () async {
  final InMemorySessionLog log = InMemorySessionLog();
  await log.append(SessionEvent.create(sessionId: 's1', seq: 0,
      type: kUserMessageEvent, data: <String, Object?>{'text': '事实 A'}));
  final InMemoryRagBackend backend = InMemoryRagBackend();
  final RagIndexer indexer = RagIndexer(
    backend: backend, embedder: _Embedder(), log: log,
    scopeOf: (String id) async => RagScope(tenantId: 't1'),
    chunking: const ChunkerConfig(
        chunkChars: 700, overlapChars: 90, maxChunkChars: 1200),
    indexVersion: 1);
  expect(await indexer.ingestSession('s1'), 1);
  expect(await indexer.ingestSession('s1'), 0);
  await log.append(SessionEvent.create(sessionId: 's1', seq: 1,
      type: kAssistantMessageEvent, data: <String, Object?>{'text': '收到'}));
  expect(await indexer.ingestSession('s1'), greaterThan(0));

  final RagIndexer failing = RagIndexer(
    backend: InMemoryRagBackend(), embedder: _ThrowingEmbedder(), log: log,
    scopeOf: (String id) async => RagScope(tenantId: 't1'),
    chunking: const ChunkerConfig(
        chunkChars: 700, overlapChars: 90, maxChunkChars: 1200),
    indexVersion: 1);
  await expectLater(failing.ingestSession('s1'), throwsA(isA<RagException>()));
  expect(await failing.backend.cursorOf('s1'), isNull);
});
```

- [ ] **Step 3: 运行确认失败**

Run: `cd packages/conatus_rag && dart test test/visibility_test.dart test/rag_index_test.dart`
Expected: FAIL。

- [ ] **Step 4: 实现**

- `TenantTagPolicy.filterFor`：`RagFilter(tenantId: scope.tenantId, anyTags: scope.visibilityTags)`。`allows`：同租户 && `scope.visibilityTags.isNotEmpty` && 交集非空。
- `RagIndexer` 暴露 `final RagIndexBackend backend;` 与 `final Embedder embedder;`（测试与 service 都要读）。
- `RagIndexer._expectedMeta`：`RagSnapshotMeta(embeddingModel: embedder.model, dimension: embedder.dimension, indexVersion: indexVersion)`；首次 `backend.meta() == null` 时 `init`。
- `ingestSession`：`scopeOf` 抛错 → `RagException('rag_scope_unresolved')`；读游标 `lastSeq`；`log.read(id)` 过滤 `event.seq > lastSeq`；无新事件返回 0；`chunkEvents(source, events, chunking)` → `embedBatch` → `upsert` → `saveCursor(RagCursor(tenantId, id, lastSeq))`；嵌入异常包成 `rag_embed_failed` 且**不写游标**。
- `ingestAll` / `ensureIngested`：遍历 `await log.list()`，逐个 `ingestSession` 求和；单个会话失败继续（记录计数），但 `RagException('rag_index_stale')` 直接向上抛。
- `rebuild`：`backend.clear()` → `init` → `ingestAll()`。

- [ ] **Step 5: 运行确认通过**

Run: `cd packages/conatus_rag && dart test test/visibility_test.dart test/rag_index_test.dart && dart analyze`
Expected: PASS。

- [ ] **Step 6: 提交**

```bash
git add packages/conatus_rag
git commit -m "feat(rag): 租户可见性策略与增量摄取"
```

---

### Task 9: RagService 与装配

**Files:**
- Create: `packages/conatus_rag/lib/src/rag_service.dart`
- Create: `packages/conatus_rag/test/rag_service_test.dart`
- Modify: `packages/conatus_rag/lib/conatus_rag.dart`

**Interfaces:**
- Consumes: Task 1–8 全部。
- Produces: `class RagService`（spec §5 方法）、`RagConfig`、`provideRag(...)`、`RetrievalAudit {tenantId, principalId, queryLength, hitIds, tokens, elapsedMs}`、`typedef RetrievalObserver = void Function(RetrievalAudit audit)`。
- `RagService({required RagIndexBackend backend, required RagConfig config, required ScopeResolver scopeOf, SessionLog? log, RetrievalObserver? audit})`；`config.embedder` 是唯一嵌入来源，不重复传；`final RagIndexBackend backend;` 对外只读（测试与运维用）。

- [ ] **Step 1: 写失败测试**

`serviceWith` 辅助（本文件内）：

```dart
RagService serviceWith(InMemoryRagBackend backend) => RagService(
      backend: backend,
      config: RagConfig(embedder: _Embedder()),
      scopeOf: (String id) async => RagScope(tenantId: 't1'),
    );
```

```dart
test('检索走策略过滤，审计不含正文，注入块带 citation', () async {
  final InMemoryRagBackend backend = InMemoryRagBackend();
  await backend.upsert(<RagChunk>[
    chunk('a', 't1', <String>{'tenant:t1'}, 0, text: '用户：我的订单号是 A-1024'),
    chunk('b', 't2', <String>{'tenant:t2'}, 1, text: '用户：别人的订单号是 B-2048'),
  ], <List<double>>[<double>[1, 0], <double>[1, 0]]);
  final List<RetrievalAudit> audits = <RetrievalAudit>[];
  final RagService service = RagService(
    backend: backend, config: RagConfig(embedder: _Embedder()),
    scopeOf: (String id) async => RagScope(tenantId: 't1'),
    audit: audits.add,
  );
  final RagScope scope = RagScope(tenantId: 't1');
  final List<RagHit> hits = await service.retrieve(
      RetrievalRequest(query: '订单号', scope: scope));
  expect(hits.map((RagHit h) => h.chunk.id), <String>['a']);
  final String block = await service.evidenceBlock('订单号', scope);
  expect(block, contains('[相关历史证据]'));
  expect(block, contains('session:s0 seq:0-0'));
  expect(audits.single.tenantId, 't1');
  expect(audits.single.hitIds, <String>['a']);
});

test('forgetSession 校验租户，forgetScope(principal) 显式拒绝', () async {
  final RagService service = serviceWith(backend);
  await service.forgetSession('s0', scope: RagScope(tenantId: 't1'));
  expect(await service.backend.count(), 0);
  await expectLater(
      service.forgetSession('s0', scope: RagScope(tenantId: 't2')),
      throwsA(isA<RagException>()));
  await expectLater(
      service.forgetScope(RagScope(tenantId: 't1', principalId: 'u1')),
      throwsA(isA<RagException>().having(
          (RagException e) => e.code, 'code', 'rag_principal_delete_unsupported')));
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd packages/conatus_rag && dart test test/rag_service_test.dart`
Expected: FAIL。

- [ ] **Step 3: 实现**

- `RagConfig`：字段见 spec §5 表，含 `embedder`、`reranker`、`visibility = const TenantTagPolicy()`、`indexVersion = 1`、尺寸参数。
- `RagService` 组合 `RagIndexer`、`DenseRetriever`、`VisibilityPolicy`；`SessionLog? log` 为 null 时 `_indexer = null` 且跳过 `ensureIngested()`（宿主自行调用 `ingestSession`），便于单元测试直接种后端数据。构造 `RagIndexer` 时用 `chunking: ChunkerConfig(chunkChars: config.chunkChars, overlapChars: config.overlapChars, maxChunkChars: config.maxChunkChars)` 与 `indexVersion: config.indexVersion`。
- `retrieve`：`ensureIngested()` → `filter = visibility.filterFor(scope)` → `retriever.retrieve` → 再 `where(visibility.allows)` → `take(request.limit)` → 记录审计（`tenantId`、`principalId`、`queryLength`、`hitIds`、`tokens`、`elapsedMs`）→ 计数。
- `String formatHits(List<RagHit> hits)`：空列表返回 `''`；否则按 `startTime` 升序生成证据块（工具与 `evidenceBlock` 共用），时间格式 `yyyy-MM-dd HH:mm`，手写补零，不引 intl。
- `evidenceBlock`：`retrieve(limit: injectLimit)`，返回 `formatHits(...)`。
- `forgetSession`：`scopeOf(sourceId)` 的 `tenantId` 与入参不一致 → `rag_scope_denied`。
- `forgetScope`：`principalId != null` → `rag_principal_delete_unsupported`；否则按租户删。
- `rebuild`：委托 indexer；`stats` 汇总 backend count + 服务计数。
- `provideRag`：`log` 缺省取 `ctx.require<SessionLog>('sessionLog')`；`backend` 缺省 `InMemoryRagBackend`；`ctx.provide('rag', service)`。工具注册在 Task 10 完成，本任务不注册。

- [ ] **Step 4: 运行确认通过**

Run: `cd packages/conatus_rag && dart test test/rag_service_test.dart && dart analyze`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_rag
git commit -m "feat(rag): RagService、装配与审计钩子"
```

---

### Task 10: `rag_search` 工具

**Files:**
- Create: `packages/conatus_rag/lib/src/rag_tool.dart`
- Create: `packages/conatus_rag/test/rag_tool_test.dart`
- Modify: `packages/conatus_rag/lib/src/rag_service.dart`（在 `provideRag` 注册工具）
- Modify: `packages/conatus_rag/lib/conatus_rag.dart`

**Interfaces:**
- Produces: `class RagSearchTool extends Tool { RagSearchTool({required RagService service, RagScope? scope}); }`，参数 `query` / `limit` / `session_id` / `from` / `to`。

- [ ] **Step 1: 写失败测试**

```dart
test('无 scope fail closed；有 scope 能取回并带 citation', () async {
  final RagSearchTool closed = RagSearchTool(service: service, scope: null);
  final ToolResult denied = await closed.call(const ToolContext(
      ToolCall(name: 'rag_search', arguments: <String, Object?>{'query': 'x'})));
  expect(denied.isError, isTrue);
  expect(denied.error!.code, 'rag_scope_missing');

  final RagSearchTool open =
      RagSearchTool(service: service, scope: RagScope(tenantId: 't1'));
  final ToolResult hit = await open.call(const ToolContext(ToolCall(
      name: 'rag_search',
      arguments: <String, Object?>{'query': '订单号', 'limit': 99})));
  expect(hit.isError, isFalse);
  expect(hit.content, contains('session:s0'));
  final Map<String, Object?> value = hit.value! as Map<String, Object?>;
  expect((value['hits']! as List<Object?>).length, lessThanOrEqualTo(15));
});

test('非法时间戳抛 ToolArgumentException', () async {
  await expectLater(
      open.call(const ToolContext(ToolCall(name: 'rag_search',
          arguments: <String, Object?>{'query': 'x', 'from': '昨天'}))),
      throwsA(isA<ToolArgumentException>()));
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd packages/conatus_rag && dart test test/rag_tool_test.dart`
Expected: FAIL。

- [ ] **Step 3: 实现**

- `name => 'rag_search'`；`riskLevel => ToolRisk.low`。
- `params`：`query` 必填；`limit` 整数默认 5；`session_id`、`from`、`to` 可选字符串。
- `scope == null` → `ToolResult.failure('未配置检索作用域，拒绝执行。', error: ToolError('rag_scope_missing', '缺少 RagScope'))`。
- 解析 ISO 时间：`DateTime.tryParse` 失败抛 `ToolArgumentException`。
- `limit` 夹在 `1..15`；调用 `service.retrieve`；空结果返回成功但 `count: 0`。
- `content` 复用 `service.evidenceBlock` 同款格式（从 service 暴露 `String formatHits(List<RagHit>)`）；`value` 给 `{count, hits: [{id, sourceKind, sourceId, firstSeq, lastSeq, score, startTime}]}`。
- 在 `provideRag` 中注册本工具：`final ToolRegistry? tools = ctx.get<ToolRegistry>('tools'); if (tools != null) ctx.effect(() => tools.register(RagSearchTool(service: service, scope: scope)));`，并把 `scope` 参数从 `provideRag` 透传到工具。

- [ ] **Step 4: 运行确认通过**

Run: `cd packages/conatus_rag && dart test test/rag_tool_test.dart test/rag_service_test.dart && dart analyze`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_rag
git commit -m "feat(rag): rag_search 工具与作用域 fail closed"
```

---

### Task 11: Agent 的 `EvidenceSource` 钩子（零依赖）

**Files:**
- Modify: `packages/conatus_agent/lib/src/agent_types.dart`
- Modify: `packages/conatus_agent/lib/src/agent_loop.dart`
- Modify: `packages/conatus_agent/lib/src/agent_provider.dart`
- Modify: `packages/conatus_agent/lib/conatus_agent.dart`
- Create: `packages/conatus_agent/test/evidence_source_test.dart`

**Interfaces:**
- Produces: `typedef EvidenceSource = Future<String> Function(String userInput);`；`AgentLoop({..., EvidenceSource? evidence})`；`provideAgentLoop(..., EvidenceSource? evidence)`。

- [ ] **Step 1: 写失败测试**

```dart
test('未接线：只有一条 system；接线：第二条 system 且 cacheable=false', () async {
  final _Provider provider = _Provider();
  final AgentLoop plain = AgentLoop(llm: provider, tools: ToolRegistry());
  await plain.run('在吗');
  expect(provider.calls.first.where((LlmMessage m) => m.role == 'system'), hasLength(1));

  final AgentLoop wired = AgentLoop(
      llm: provider, tools: ToolRegistry(),
      evidence: (String input) async => '[相关历史证据]\n- 事实 A');
  await wired.run('在吗');
  final List<LlmMessage> systems = provider.calls.last
      .where((LlmMessage m) => m.role == 'system').toList();
  expect(systems, hasLength(2));
  expect(systems.last.content, contains('事实 A'));
  expect(systems.last.cacheable, isFalse);
  expect(systems.first.cacheable, isTrue);
});

test('钩子抛错/返回空串都不注入、不影响收口', () async {
  final _Provider provider = _Provider();
  final AgentLoop broken = AgentLoop(llm: provider, tools: ToolRegistry(),
      evidence: (String input) async => throw StateError('端点挂了'));
  final AgentTurn turn = await broken.run('在吗');
  expect(turn.reply, '你好');
  expect(provider.calls.last.where((LlmMessage m) => m.role == 'system'),
      hasLength(1));
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd packages/conatus_agent && dart test test/evidence_source_test.dart`
Expected: FAIL（`evidence` 参数不存在）。

- [ ] **Step 3: 实现**

- `agent_types.dart` 末尾加 typedef，并在 `conatus_agent.dart` 的 `agent_types.dart` show 列表加 `EvidenceSource`。
- `AgentLoop`：构造参数 `this.evidence`、字段 `final EvidenceSource? evidence;`。
- `_runOnce`：在 `_historyStart = await compactSession(...)` 之后取证据：

```dart
final String evidenceText = await _readEvidence(userInput);
final List<LlmMessage> messages = <LlmMessage>[
  LlmMessage('system', _systemText(userInput), cacheable: true),
  if (evidenceText.isNotEmpty) LlmMessage('system', evidenceText),
  ...deriveAgentMessages(recentAgentEvents(session, _historyStart)),
];
```

- `_readEvidence`：null → `''`；`try { return (await evidence!(input)).trim(); } on AgentCancelled { rethrow; } catch (_) { return ''; }`。
- `agent_provider.dart`：加 `EvidenceSource? evidence` 参数并透传给 `AgentLoop`。
- **不改** `buildSystemText`、不改 pubspec。

测试里的 `_Provider` 与 `agent_loop_test.dart` 的 `_ScriptedProvider` 同构：记录 `calls`，`chat` 返回 `LlmResult(content: '你好', provider: 'scripted', model: 'm')`，`chatStream` 返回空流。

- [ ] **Step 4: 运行确认通过**

Run: `cd packages/conatus_agent && dart test test/evidence_source_test.dart test/agent_loop_test.dart && dart analyze`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_agent
git commit -m "feat(agent): 可选 EvidenceSource 证据钩子（不依赖 rag）"
```

---

### Task 12: 集成测试与伞包接线

**Files:**
- Modify: `pubspec.yaml`（根，加 `conatus_rag: {path: packages/conatus_rag}`）
- Modify: `lib/conatus.dart`（export + 包注释）
- Create: `test/integration/rag_test.dart`

**Interfaces:**
- Consumes: `provideRag`、`provideAgentLoop(evidence:)`、`SessionLog`。
- Produces: 跨租户隔离与注入链路的回归测试。

- [ ] **Step 1: 接线**

根 `pubspec.yaml` 的 `dependencies` 加 `conatus_rag: {path: packages/conatus_rag}`（按字母序）；`lib/conatus.dart` 加 `export 'package:conatus_rag/conatus_rag.dart';` 并在注释列表补一行。

- [ ] **Step 2: 写失败测试**

```dart
class _ConstantEmbedder implements Embedder {
  @override String get model => 'fixture';
  @override int get dimension => 2;
  @override Future<List<double>> embed(String text) async => <double>[1, 0];
  @override Future<List<List<double>>> embedBatch(List<String> texts) async =>
      <List<double>>[for (final String _ in texts) <double>[1, 0]];
  @override void dispose() {}
}

test('租户 A 的事实可注入/可检索，租户 B 一律取不到；forget 后消失', () async {
  final Directory dir = await Directory.systemTemp.createTemp('rag-it');
  final SessionLog log = PersistenceSessionLog(JsonlSessionPersistence(dir: dir.path));
  await log.append(SessionEvent.create(sessionId: 'a-s1', seq: 0,
      type: kUserMessageEvent, data: <String, Object?>{'text': '我的工号是 E-778'}));

  final Context app = Context.root();
  provideTools(app);
  provideSystemPrompt(app);
  provideSessionLog(app, log: log);
  final RagService rag = provideRag(app,
      config: RagConfig(embedder: _ConstantEmbedder()),
      scopeOf: (String id) async => RagScope(
          tenantId: id.startsWith('a-') ? 'ta' : 'tb',
          visibilityTags: const <String>{}));

  final RagScope ta = RagScope(tenantId: 'ta');
  final RagScope tb = RagScope(tenantId: 'tb');
  await rag.ingestSession('a-s1');
  expect(await rag.retrieve(RetrievalRequest(query: '工号', scope: ta)), isNotEmpty);
  expect(await rag.retrieve(RetrievalRequest(query: '工号', scope: tb)), isEmpty);

  final RagSearchTool asB = RagSearchTool(service: rag, scope: tb);
  final ToolResult denied = await asB.call(const ToolContext(
      ToolCall(name: 'rag_search', arguments: <String, Object?>{'query': '工号'})));
  expect((denied.value! as Map<String, Object?>)['count'], 0);

  final ScriptedLlm llm = ScriptedLlm(<LlmResult>[text('好的')]);
  final AgentLoop loop = AgentLoop(llm: llm, tools: ToolRegistry(),
      evidence: (String q) => rag.evidenceBlock(q, tb));
  await loop.run('我的工号是多少');
  expect(llm.requests.single.any((LlmMessage m) => m.content.contains('E-778')), isFalse);

  await rag.forgetSession('a-s1', scope: ta);
  expect(await rag.retrieve(RetrievalRequest(query: '工号', scope: ta)), isEmpty);
});
```

- [ ] **Step 3: 运行确认失败**

Run: `dart pub get && dart test test/integration/rag_test.dart`
Expected: FAIL（根包尚无依赖/导出）。

- [ ] **Step 4: 让测试通过**

补 `_ConstantEmbedder`（上文已定义，所有文本同向，足够验证隔离链路）；导入 `dart:io`、`package:conatus/conatus.dart`、`helpers/scripted_llm.dart`。断言 justification：`RagSearchTool` 对空结果返回成功 + `count: 0`，所以用 `value['count']` 而不是 `isError`。

- [ ] **Step 5: 运行确认通过**

Run: `dart test test/integration/rag_test.dart`
Expected: PASS。

- [ ] **Step 6: 提交**

```bash
git add pubspec.yaml lib/conatus.dart test/integration/rag_test.dart
git commit -m "test(rag): 跨租户隔离与证据注入集成测试"
```

---

### Task 13: 离线评测（coverage@5 对照）

**Files:**
- Create: `packages/conatus_rag/test/recall_eval_test.dart`

**Interfaces:**
- Consumes: `RagService`、`RagIndexer`、`RagConfig`、`InMemoryRagBackend`、`InMemorySessionLog`。
- Produces: 确定性评测，证明向量检索在同义改写查询上优于现有词元召回。

- [ ] **Step 1: 写测试**

- `_FixtureEmbedder`：内置 `Map<String, List<double>>`，把「工号 / 员工编号 / 我的编号」「报销 / 费用报销 / 差旅费」等映射到同一基向量，其余 hash 到固定维度（沿用字符 bigram 思路，但同义组强制同向）。
- 种 3 段会话、20 个问题（改写 / 多跳 / 时序 / 跨会话各 5）。
- 指标：注入块（`evidenceBlock`）是否包含 gold 事实；词元基线用 `MemoryStore.recall` 或同样的 `_tokenize` 逻辑实现 `_keywordHit`。
- 断言：

```dart
expect(ragCoverage, greaterThanOrEqualTo(keywordCoverage));
expect(ragCoverage, greaterThanOrEqualTo(0.8));
```

- [ ] **Step 2: 运行确认失败（先写断言，未实现 fixture 时）**

Run: `cd packages/conatus_rag && dart test test/recall_eval_test.dart`
Expected: FAIL。

- [ ] **Step 3: 实现 fixture 与基线**

只写测试内辅助类，不新增生产代码。

- [ ] **Step 4: 运行确认通过**

Run: `cd packages/conatus_rag && dart test test/recall_eval_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_rag/test/recall_eval_test.dart
git commit -m "test(rag): 离线 coverage@5 评测对照"
```

---

### Task 14: 文档与收尾

**Files:**
- Modify: `README.md`（包表 + `### rag` 用法节）
- Modify: `AGENTS.md`（包计数、依赖方向）
- Modify: `packages/conatus_rag/README.md`
- Modify: `packages/conatus_rag/CHANGELOG.md`

**Interfaces:**
- 无新代码。

- [ ] **Step 1: 写包 README**

必须覆盖：定位（会话历史检索，不是企业知识平台）、最小示例（`provideRag` + `provideAgentLoop(evidence:)` + 独立工具）、scope/权限模型（`tenant:` 标签、fail closed、`ScopeResolver` 不许猜）、配置默认值、成本与延迟、隐私边界（原文落盘、逻辑隔离 vs 物理隔离）、删除 API、`rebuild()` 时机。

- [ ] **Step 2: 写根 README / AGENTS**

- 根 README 包表加 `conatus_rag`（稳定包）；新增 `### rag` 节（150 行以内，指向包 README 的细节）。
- AGENTS.md：包计数改为 15 稳定 + 12 实验性（另有 `conatus_code` 子模块，共 28 个目录）；依赖方向补一行「rag 是可选能力包，不进入 agent 依赖闭包」。

- [ ] **Step 3: 全量校验**

Run:
```bash
dart pub get && dart analyze --fatal-infos && dart format --set-exit-if-changed . 
for d in packages/conatus_rag packages/conatus_agent; do (cd "$d" && dart test); done
dart test
```
Expected: 全部 PASS，无格式差异。

- [ ] **Step 4: 提交并推送**

```bash
git add README.md AGENTS.md packages/conatus_rag/README.md packages/conatus_rag/CHANGELOG.md
git commit -m "docs(rag): 补包文档、根 README 与 AGENTS 计数"
git push
```

---

## 计划自检记录

- **Spec 覆盖**：租户/权限（Task 8/9/12）、citation（Task 1/3/9）、token 预算（Task 7）、可替换后端（Task 4/5）、审计（Task 9）、索引版本/重建（Task 4/8/9）、agent 零依赖（Task 11）、工具 fail closed（Task 10）、删除（Task 9）、离线评测（Task 13）、文档（Task 14）。
- **未纳入本计划**（spec §13 明确后续）：hybrid 检索、pgvector 后端、文档语料、ACL 同步、配额/DLP。
- **类型一致性**：`RagScope.visibilityTags` 在所有任务中按「含 `tenant:<id>`」处理；`RagFilter.anyTags` 一律表示可见标签交集；`RagHit.chunk` 是唯一证据载体。
- **Review Focus 五项**逐条落到测试：Task 8/12（跨租户）、Task 8（空标签）、Task 6/8（坏嵌入）、Task 3（超长输出）、Task 5（损坏文件）。
