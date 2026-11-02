# 阶段 0 第 1 周运行器骨架 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `products/conatus_work` 里做出最小任务运行器骨架，让一张空任务卡跑通并写出合法的 `run.json`。

**Architecture:** 运行器是一个库（`lib/src/runner/`）+ 薄 CLI（`bin/runner.dart`）。Conatus 的 `Context` 只在 `assembly.dart` 内组装一次，出口是普通对象 `RunScope`；写边界由 `RootedFileSystem` 装饰器在 `'fs'` 服务上强制，`move` / `mkdir` 是它的额外方法并由两个工具暴露。任务边界映射为「一任务 = 一轮」：`reset`/`bind` 取 `startTurn`，收口 `recordTurn`。

**Tech Stack:** Dart ^3.11.0（纯 Dart）、conatus 伞包（Context / fs / 工具 / checkpoint / session）、`crypto`（sha256）、`package:test`。

**Spec:** `products/conatus_work/docs/2026-11-02-week1-runner-skeleton-design.md`

## Global Constraints

- Dart SDK `^3.11.0`，纯 Dart，不引入 Flutter 依赖。
- 新增第三方依赖只允许 `crypto: ^3.0.0`。
- 单文件 ≤ 200 行，单函数 ≤ 40 行，函数参数 ≤ 4 个，`if/else/switch` 合计 ≤ 3。
- 布尔变量 / 函数用状态词，禁止 `is/has/can/should` 前缀。
- 包内导入用相对路径（`prefer_relative_imports`），字符串用单引号。
- 面向用户的文案用中文。
- 不改 `packages/conatus_code`；不改 nava 的 `ReadOnlyPathGuard`。
- 第 1 周不装 shell、不接 Agent Loop、不读模型环境变量、不联网。
- 提交信息：Conventional Commits + 中文，如 `feat(runner): 任务卡模型与校验`。
- 每个任务在 `products/conatus_work` 下执行：`cd products/conatus_work`。

## Review Focus

以下 5 个失败模式最容易在真实使用中咬人，每个都在指定任务的测试里被钉住：

1. **前缀比较写成字符串前缀**：`out-evil/` 被当成 `out/` 放行 —— Task 3。
2. **符号链接逃逸**：`out/link → /tmp` 后写 `out/link/x` 落到根外 —— Task 3。
3. **删除工作区根**：`remove('.')` 把整个工作区抹掉 —— Task 3。
4. **快照失败被误当任务失败**：`recordTurn` 返回错误串却改写 `status` —— Task 2 的纯函数映射 + Task 7 的接线。
5. **相对路径按错基准解析**：`--workspace` 与 `workspace.root` 叠加两次 —— Task 9 的 CLI 测试。

---

### Task 1: 依赖与任务卡模型

**Files:**
- Create: `products/conatus_work/lib/src/runner/task_spec.dart`
- Test: `products/conatus_work/test/unit/task_spec_test.dart`

**Interfaces:**
- Consumes: 无
- Produces:
  - `class TaskSpec`：字段 `String id, chain, title, prompt, workspaceRoot; List<String> read, write, inputs, expectedArtifacts, acceptance; bool allowNetwork; int maxMinutes; double maxCostUsd; bool checkpointEnabled; int checkpointKeep;`
  - `static TaskSpec TaskSpec.parse(Map<String, Object?> json)`
  - `static Future<TaskSpec> TaskSpec.load(String path)`
  - `class TaskSpecError implements Exception { TaskSpecError(this.field, this.message); final String field, message; }`
  - `const Set<String> kTaskChains = {'research', 'csv', 'organize'};`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:conatus_work/src/runner/task_spec.dart';
import 'package:test/test.dart';

Map<String, Object?> validCard({
  Map<String, Object?>? workspace,
  Object? network = 'deny',
  Object? keep = 30,
  Object? chain = 'research',
}) =>
    <String, Object?>{
      'id': 'research-v01',
      'chain': chain,
      'title': '调研并写报告',
      'workspace': workspace ??
          <String, Object?>{
            'root': 'var/workspaces/r1',
            'read': <String>['inbox'],
            'write': <String>['out'],
          },
      'inputs': <String>[],
      'prompt': '读 brief.md 写报告',
      'network': network,
      'expectedArtifacts': <String>['out/report.md'],
      'acceptance': <String>['有引用'],
      'limits': <String, Object?>{'maxMinutes': 20, 'maxCostUsd': 1.5},
      'checkpoint': <String, Object?>{'enabled': true, 'keep': keep},
    };

void main() {
  test('合法任务卡解析出全部字段', () {
    final TaskSpec spec = TaskSpec.parse(validCard());
    expect(spec.id, 'research-v01');
    expect(spec.chain, 'research');
    expect(spec.allowNetwork, isFalse);
    expect(spec.read, <String>['inbox']);
    expect(spec.write, <String>['out']);
    expect(spec.checkpointKeep, 30);
  });

  test('缺 network / 未知 chain / 非法路径 / keep<1 全部拒绝', () {
    final List<Map<String, Object?>> bad = <Map<String, Object?>>[
      validCard(network: null),
      validCard(chain: 'unknown'),
      validCard(workspace: <String, Object?>{
        'root': 'var/workspaces/r1',
        'read': <String>['/abs'],
        'write': <String>['out'],
      }),
      validCard(workspace: <String, Object?>{
        'root': 'var/workspaces/r1',
        'read': <String>[],
        'write': <String>['../out'],
      }),
      validCard(workspace: <String, Object?>{
        'root': 'var/workspaces/r1',
        'read': <String>[],
        'write': <String>[],
      }),
      validCard(keep: 0),
    ];
    for (final Map<String, Object?> card in bad) {
      expect(() => TaskSpec.parse(card), throwsA(isA<TaskSpecError>()));
    }
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd products/conatus_work && dart test test/unit/task_spec_test.dart`
Expected: FAIL（`task_spec.dart` 不存在）

- [ ] **Step 3: 实现 `TaskSpec`**

实现要求：`allowNetwork` 由 `network` 字符串映射（`allow` → true，`deny` → false，其他值抛 `TaskSpecError('network', …)`）；`read` / `write` / `inputs` / `expectedArtifacts` 的每一项都必须是相对路径且不含 `..`（不引 path 包：判是否以 `/` 开头或含盘符 `:`，并按 `/` 与 `\\` 切段检查 `..`）；`workspace.write` 非空；`checkpointKeep >= 1`；未知字段忽略。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd products/conatus_work && dart test test/unit/task_spec_test.dart`
Expected: PASS（2 个测试）

- [ ] **Step 5: 提交**

```bash
cd products/conatus_work
git add pubspec.yaml lib/src/runner/task_spec.dart test/unit/task_spec_test.dart
git commit -m "feat(runner): 任务卡模型与校验"
```

---

### Task 2: 运行目录与 `run.json` 存储

**Files:**
- Modify: `products/conatus_work/pubspec.yaml`
- Create: `products/conatus_work/lib/src/runner/run_paths.dart`
- Create: `products/conatus_work/lib/src/runner/hash.dart`
- Create: `products/conatus_work/lib/src/runner/run_store.dart`
- Test: `products/conatus_work/test/unit/run_store_test.dart`

**Interfaces:**
- Consumes: 无
- Produces:
  - `String newRunId(DateTime now, [Random? random])` → `run_<yyyyMMdd-HHmmss>-<4 hex>`
  - `class RunPaths { RunPaths({required this.runsDir, required this.runId}); String get runDir, runJsonPath, eventsPath, artifactsDir, abortFlagPath; Future<void> create(); }`
  - `enum RunStatus { running, succeeded, failed, aborted }`
  - `enum FailureCategory { artifact, llm, tool, timeout, budget, checkpoint, internal }`
  - `enum CheckpointStatus { pending, ok, error }`
  - `class ArtifactCheck { ArtifactCheck({required this.path, this.bytes = 0, this.sha256 = '', this.passed = false, this.reason}); String path; int bytes; String sha256; bool passed; String? reason; }`
  - `class HumanEdit { HumanEdit({required this.at, required this.artifact, required this.note, this.sha256}); DateTime at; String artifact; String note; String? sha256; }`
  - `class RunFailure { FailureCategory? category; String? message; }`
  - `class RunRecord`（字段全部可变）：`String runId, taskId, chain, taskPath, workspaceRoot, sessionId; int pid; DateTime startedAt; DateTime? endedAt; RunStatus status; String? model; int resumeCount; String? rerunOf; int? startTurn, endTurn; CheckpointStatus checkpointStatus; String? checkpointError; int inputTokens, outputTokens; double costUsd; List<ArtifactCheck> artifacts; List<String> tools; String? forkSessionId; List<HumanEdit> humanEdits; RunFailure failure;`
  - `RunRecord({required String runId, taskId, chain, taskPath, workspaceRoot, sessionId, int pid, DateTime startedAt})`，其余字段有默认值
  - `Map<String, Object?> RunRecord.toJson()` / `factory RunRecord.fromJson(Map<String, Object?>)`
  - `class RunStore { RunStore(this.paths); Future<void> save(RunRecord); Future<RunRecord> load(); }`
  - `String sha256Hex(List<int> bytes)`
  - `RunRecord applySnapshot(RunRecord record, String? error)`（只改 `checkpointStatus` / `checkpointError`，不动 `status`）

- [ ] **Step 1: 写失败测试**

```dart
import 'dart:io';
import 'package:conatus_work/src/runner/hash.dart';
import 'package:conatus_work/src/runner/run_paths.dart';
import 'package:conatus_work/src/runner/run_store.dart';
import 'package:test/test.dart';

void main() {
  test('runId 形状稳定', () {
    expect(newRunId(DateTime(2026, 11, 2, 10, 15, 0)),
        matches(RegExp(r'^run_20261102-101500-[0-9a-f]{4}$')));
  });

  test('run.json 往返且写入原子', () async {
    final Directory tmp = Directory.systemTemp.createTempSync('run_store_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final RunPaths paths =
        RunPaths(runsDir: tmp.path, runId: 'run_20261102-101500-a1b2');
    await paths.create();
    final RunStore store = RunStore(paths);
    final RunRecord record = RunRecord(
      runId: paths.runId,
      taskId: 'research-v01',
      chain: 'research',
      taskPath: '/tmp/tasks/research-v01.json',
      workspaceRoot: 'var/workspaces/r1',
      sessionId: 'events',
      pid: 42,
      startedAt: DateTime.parse('2026-11-02T10:15:00+08:00'),
    );
    await store.save(record);
    final RunRecord loaded = await store.load();
    expect(loaded.taskId, 'research-v01');
    expect(loaded.chain, 'research');
    expect(loaded.turns.start, isNull);
    expect(File('${paths.runJsonPath}.tmp').existsSync(), isFalse);
  });

  test('快照失败只改检查点状态', () async {
    final RunRecord record = RunRecord(
      runId: 'r', taskId: 't', chain: 'csv', taskPath: '/t.json',
      workspaceRoot: 'w', sessionId: 'events', pid: 1,
      startedAt: DateTime(2026, 11, 2),
    )..status = RunStatus.succeeded;
    final RunRecord patched = applySnapshot(record, 'disk full');
    expect(patched.status, RunStatus.succeeded);
    expect(patched.checkpointStatus, CheckpointStatus.error);
    expect(patched.checkpointError, 'disk full');
  });

  test('sha256 与已知向量一致', () {
    expect(sha256Hex(<int>[0x61, 0x62, 0x63]),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd products/conatus_work && dart test test/unit/run_store_test.dart`
Expected: FAIL（文件不存在）

- [ ] **Step 3: 实现三个文件**

先 `pubspec.yaml` 在 `dependencies:` 下加 `crypto: ^3.0.0`（按字母序放在 `conatus` 前），跑 `dart pub get`。

- `hash.dart` 只放 `sha256Hex`（`crypto` 的 `sha256.convert` + `toString()`）。
- `run_paths.dart`：`newRunId` 用本地时间格式化（不引 intl）；`create()` 建 `runDir` 与 `artifactsDir`。
- `run_store.dart`：`save` 先写 `runJsonPath.tmp` 再 `File.rename`（同一目录内原子）；`load` 读并 `fromJson`；`toJson` 用 ISO-8601 字符串、枚举用 `name`；`RunRecord` 构造函数给 `status: running`、`checkpointStatus: pending`、`resumeCount: 0`、空集合默认值。`applySnapshot` 按测试语义实现。
- 时间戳一律带时区偏移（`toIso8601String()` 会丢本地偏移，用 `DateTime.now()` 时保留 `+08:00` 只需存 `toLocal().toIso8601String()`；读取时 `DateTime.parse` 即可）。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd products/conatus_work && dart test test/unit/run_store_test.dart`
Expected: PASS（4 个测试）

- [ ] **Step 5: 提交**

```bash
cd products/conatus_work
git add pubspec.yaml lib/src/runner/run_paths.dart lib/src/runner/hash.dart lib/src/runner/run_store.dart test/unit/run_store_test.dart
git commit -m "feat(runner): 运行目录与 run.json 存储"
```

---

### Task 3: `RootedFileSystem` 读写闸门

**Files:**
- Create: `products/conatus_work/lib/src/tools/rooted_fs.dart`
- Test: `products/conatus_work/test/unit/rooted_fs_test.dart`

**Interfaces:**
- Consumes: `package:conatus/conatus.dart` 的 `FileSystem`、`FsTarget`、`FsError`、`FsErrorCode`、`FsWriteOutcome`、`FsEditOutcome`、`FsInfo`、`FsPathInfo`、`FsDirEntry`、`LocalFileSystem`、`underReadOnlyRoot`、`normalizeReadOnlyPath`、`realPathViaAncestor`
- Produces: `class RootedFileSystem implements FileSystem { RootedFileSystem({required FileSystem inner, required String root, required Iterable<String> readPrefixes, required Iterable<String> writePrefixes}); }`（`readPrefixes` 是**完整读集合**，调用方传 `read ∪ write`）

- [ ] **Step 1: 写失败测试**

```dart
import 'dart:io';
import 'package:conatus/conatus.dart';
import 'package:conatus_work/src/tools/rooted_fs.dart';
import 'package:test/test.dart';

RootedFileSystem openFs(String root) => RootedFileSystem(
      inner: LocalFileSystem(cwd: root),
      root: root,
      readPrefixes: <String>['inbox', 'out'],
      writePrefixes: <String>['out'],
    );

Matcher sandboxDenied() => throwsA(isA<FsError>()
    .having((FsError e) => e.code, 'code', FsErrorCode.sandboxDenied));

void main() {
  late Directory tmp;
  late RootedFileSystem fs;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('rooted_fs_');
    for (final String d in <String>['inbox', 'out']) {
      Directory('${tmp.path}/$d').createSync(recursive: true);
    }
    fs = openFs(tmp.path);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('写 out/ 放行', () async {
    final FsTarget t = await fs.resolve('out/report.md');
    await fs.writeText(t, 'ok');
    expect(File('${tmp.path}/out/report.md').readAsStringSync(), 'ok');
  });

  test('out-evil/ 与 ../ 拒绝', () async {
    Directory('${tmp.path}/out-evil').createSync();
    await expectLater(fs.resolve('out-evil/x.md').then((t) => fs.writeText(t, 'x')),
        sandboxDenied());
    await expectLater(fs.resolve('../escape.md').then((t) => fs.writeText(t, 'x')),
        sandboxDenied());
  });

  test('符号链接逃逸拒绝', () async {
    final String outside = Directory.systemTemp.createTempSync('outside_').path;
    addTearDown(() => Directory(outside).deleteSync(recursive: true));
    Link('${tmp.path}/out/link').createSync(outside);
    await expectLater(
        fs.resolve('out/link/x.md').then((t) => fs.writeText(t, 'x')),
        sandboxDenied());
  });

  test('读白名单：inbox 放行、根外拒绝，out 因可写而可读', () async {
    File('${tmp.path}/inbox/brief.md').writeAsStringSync('b');
    expect(await fs.readText(await fs.resolve('inbox/brief.md')), 'b');
    expect(await fs.readText(await fs.resolve('out/../inbox/brief.md')), 'b');
    await expectLater(fs.resolve('/etc/hosts').then((t) => fs.readText(t)),
        sandboxDenied());
  });

  test('根可列举不可写，remove(root) 拒绝', () async {
    expect((await fs.listDir(await fs.resolve('.'))).map((e) => e.name),
        containsAll(<String>['inbox', 'out']));
    await expectLater(fs.resolve('.').then((t) => fs.writeText(t, 'x')),
        sandboxDenied());
    await expectLater(fs.remove(await fs.resolve('.')), sandboxDenied());
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd products/conatus_work && dart test test/unit/rooted_fs_test.dart`
Expected: FAIL（`rooted_fs.dart` 不存在）

- [ ] **Step 3: 实现闸门**

构造时计算 `_rootReal = normalizeReadOnlyPath(realPathViaAncestor(root) ?? Directory(root).absolute.path)`，每个前缀算 `_prefixReal = realPathViaAncestor('$_rootReal/$prefix') ?? '$_rootReal/$prefix'`（规范化）。所有判定用 `underReadOnlyRoot(candidate, base)`，`candidate` 取 `inner.processPath(target)`（即 realpath）。

网关映射：`stat` / `lstat` / `listDir` / `readText` / `readBytes` 走读集合；`writeText` / `editText` 走写集合；`remove` 走写集合且拒绝「目标 == 根」或「目标包含根」。根目录本身允许 `stat` / `listDir`，不允许写。拒绝抛 `FsError(FsErrorCode.sandboxDenied, '目标不在允许的写入范围内：<displayPath>')`（文案不含绝对根）。

拷一份 `ReadOnlyPathGuard` 的透传方法形状，保证 `implements FileSystem` 编译通过。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd products/conatus_work && dart test test/unit/rooted_fs_test.dart`
Expected: PASS（5 个测试）

- [ ] **Step 5: 提交**

```bash
cd products/conatus_work
git add lib/src/tools/rooted_fs.dart test/unit/rooted_fs_test.dart
git commit -m "feat(fs): allow-list 写边界装饰器"
```

---

### Task 4: `mkdir` / `move` 与两个工具

**Files:**
- Modify: `products/conatus_work/lib/src/tools/rooted_fs.dart`
- Create: `products/conatus_work/lib/src/tools/mkdir.dart`
- Create: `products/conatus_work/lib/src/tools/move.dart`
- Test: `products/conatus_work/test/unit/fs_ops_tools_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `RootedFileSystem`
- Produces:
  - `class MoveResult { final String fromPath, toPath; final int bytes; }`
  - `Future<void> RootedFileSystem.mkdir(String path)`
  - `Future<MoveResult> RootedFileSystem.move(String from, String to)`
  - `class MkdirTool extends Tool { MkdirTool({required this.fs}); final RootedFileSystem fs; }`（`name = 'mkdir'`，`riskLevel = ToolRisk.low`，参数 `path`）
  - `class MoveTool extends Tool { MoveTool({required this.fs}); final RootedFileSystem fs; }`（`name = 'move'`，`riskLevel = ToolRisk.medium`，参数 `from` / `to`，`pathParams = ['from', 'to']`）

- [ ] **Step 1: 写失败测试**

```dart
import 'dart:io';
import 'package:conatus/conatus.dart';
import 'package:conatus_work/src/tools/mkdir.dart';
import 'package:conatus_work/src/tools/move.dart';
import 'package:conatus_work/src/tools/rooted_fs.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late RootedFileSystem fs;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('fs_ops_');
    for (final String d in <String>['inbox', 'out']) {
      Directory('${tmp.path}/$d').createSync(recursive: true);
    }
    fs = RootedFileSystem(
      inner: LocalFileSystem(cwd: tmp.path),
      root: tmp.path,
      readPrefixes: <String>['inbox', 'out'],
      writePrefixes: <String>['out'],
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('mkdir 递归创建且幂等', () async {
    await fs.mkdir('out/a/b');
    await fs.mkdir('out/a/b');
    expect(Directory('${tmp.path}/out/a/b').existsSync(), isTrue);
    await expectLater(fs.mkdir('inbox/x'), throwsA(isA<FsError>()));
  });

  test('move 重命名，目标已存在则失败', () async {
    File('${tmp.path}/out/a.txt').writeAsStringSync('12345');
    final MoveResult result = await fs.move('out/a.txt', 'out/b.txt');
    expect(result.bytes, 5);
    expect(File('${tmp.path}/out/b.txt').existsSync(), isTrue);
    File('${tmp.path}/out/c.txt').writeAsStringSync('c');
    await expectLater(fs.move('out/b.txt', 'out/c.txt'), throwsA(isA<FsError>()));
    expect(File('${tmp.path}/out/c.txt').readAsStringSync(), 'c');
  });

  test('move 源在只读区或目标越界都拒绝', () async {
    File('${tmp.path}/inbox/x.txt').writeAsStringSync('x');
    await expectLater(fs.move('inbox/x.txt', 'out/x.txt'), throwsA(isA<FsError>()));
    await expectLater(fs.move('out/x.txt', '../y.txt'), throwsA(isA<FsError>()));
  });

  test('工具形状与执行', () async {
    final MkdirTool mkdir = MkdirTool(fs: fs);
    expect(mkdir.name, 'mkdir');
    expect(mkdir.params.map((p) => p.name), <String>['path']);
    final ToolResult ok = await mkdir.call(const ToolContext(
        ToolCall(name: 'mkdir', arguments: <String, Object?>{'path': 'out/d'})));
    expect(ok.isError, isFalse);
    final MoveTool move = MoveTool(fs: fs);
    expect(move.name, 'move');
    expect(move.pathParams, <String>['from', 'to']);
    expect(move.riskLevel, ToolRisk.medium);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd products/conatus_work && dart test test/unit/fs_ops_tools_test.dart`
Expected: FAIL（`mkdir` 未定义）

- [ ] **Step 3: 实现**

- `mkdir`：`resolve(path)` → 写网关 → `Directory(processPath).create(recursive: true)`；已存在且是目录时直接返回。
- `move`：resolve 两端 → 两端都过写网关 → 源不存在抛 `FsError(FsErrorCode.notFound, …)` → 目标已存在抛 `FsError(FsErrorCode.ioError, '目标已存在：<to>')` → 建目标父目录（`Directory(parent).create(recursive: true)`，父目录必在写根内）→ 按 `stat` 类型选 `File.rename` 或 `Directory.rename` → 源为文件时把 `size` 填进 `MoveResult.bytes`，目录填 0。
- 工具 `call` 内用 `context.str('path')` / `str('from')` / `str('to')`，成功返回 `ToolResult.success(..., value: <String, Object?>{...})`，`FsError` 包成 `ToolResult.failure(e.message, error: ToolError(e.code.code, e.message))`。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd products/conatus_work && dart test test/unit/fs_ops_tools_test.dart`
Expected: PASS（4 个测试）

- [ ] **Step 5: 提交**

```bash
cd products/conatus_work
git add lib/src/tools/rooted_fs.dart lib/src/tools/mkdir.dart lib/src/tools/move.dart test/unit/fs_ops_tools_test.dart
git commit -m "feat(fs): move 与 mkdir 工具"
```

---

### Task 5: 产物校验

**Files:**
- Create: `products/conatus_work/lib/src/runner/artifacts.dart`
- Test: `products/conatus_work/test/unit/artifacts_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `ArtifactCheck`、`sha256Hex`
- Produces: `Future<List<ArtifactCheck>> checkArtifacts({required String root, required List<String> expected})`

- [ ] **Step 1: 写失败测试**

```dart
import 'dart:io';
import 'package:conatus_work/src/runner/artifacts.dart';
import 'package:conatus_work/src/runner/hash.dart';
import 'package:conatus_work/src/runner/run_store.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('artifacts_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('缺失 / 空 / 正常三种判定', () async {
    Directory('${tmp.path}/out').createSync();
    File('${tmp.path}/out/empty.md').writeAsStringSync('');
    File('${tmp.path}/out/ok.md').writeAsStringSync('abc');
    final List<ArtifactCheck> checks = await checkArtifacts(
      root: tmp.path,
      expected: <String>['out/missing.md', 'out/empty.md', 'out/ok.md'],
    );
    expect(checks[0].passed, isFalse);
    expect(checks[0].reason, 'missing');
    expect(checks[1].passed, isFalse);
    expect(checks[1].reason, 'empty');
    expect(checks[2].passed, isTrue);
    expect(checks[2].bytes, 3);
    expect(checks[2].sha256, sha256Hex(<int>[0x61, 0x62, 0x63]));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd products/conatus_work && dart test test/unit/artifacts_test.dart`
Expected: FAIL

- [ ] **Step 3: 实现**

按 `expected` 顺序逐个 `File('$root/$path')`：不存在 → `passed: false, reason: 'missing', bytes: 0, sha256: ''`；存在但 `length == 0` → `reason: 'empty'`；否则读字节算 `sha256Hex`。目录视为 `reason: 'notFile'`。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd products/conatus_work && dart test test/unit/artifacts_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
cd products/conatus_work
git add lib/src/runner/artifacts.dart test/unit/artifacts_test.dart
git commit -m "feat(runner): 产物存在性与哈希校验"
```

---

### Task 6: 工作区准备与 Context 装配

**Files:**
- Create: `products/conatus_work/lib/src/runner/workspace.dart`
- Create: `products/conatus_work/lib/src/runner/assembly.dart`
- Test: `products/conatus_work/test/integration/assembly_test.dart`

**Interfaces:**
- Consumes: Task 1 `TaskSpec`、Task 2 `RunPaths`、Task 3/4 `RootedFileSystem` / `MkdirTool` / `MoveTool`
- Produces:
  - `class WorkspacePlan { final String rootAbsolute; final List<String> readPrefixes, writePrefixes; }`
  - `String resolveWorkspaceRoot({required TaskSpec task, String? rootOverride, String cwd = ''})`——`cwd` 为空时取 `Directory.current.path`；绝对路径原样规范化，相对路径拼到 `cwd` 上
  - `Future<WorkspacePlan> prepareWorkspace({required TaskSpec task, String? rootOverride})`——用 `resolveWorkspaceRoot` 得到根，建根与写前缀目录
  - `CheckpointPolicy productCheckpointPolicy()` → `excludedPrefixes: ['.conatus_work', '.git']`
  - `class RunScope { final Context ctx; final RootedFileSystem fs; final CheckpointManager checkpoint; final SessionStore sessionStore; final Session session; final RunPaths paths; final List<String> toolNames; Future<void> dispose(); }`
  - `Future<RunScope> assembleRun({required TaskSpec task, required WorkspacePlan workspace, required RunPaths paths, bool fresh = true})`（`fresh` 为 true 时 `reset(session.id)` 写 turn 0；false 时 `bind` 接管已有时间线；两者都随后 `flush()`）

- [ ] **Step 1: 写失败测试**

```dart
import 'dart:io';
import 'package:conatus/conatus.dart';
import 'package:conatus_work/src/runner/assembly.dart';
import 'package:conatus_work/src/runner/run_paths.dart';
import 'package:conatus_work/src/runner/task_spec.dart';
import 'package:conatus_work/src/runner/workspace.dart';
import 'package:test/test.dart';

TaskSpec card(String root) => TaskSpec.parse(<String, Object?>{
      'id': 'research-v01',
      'chain': 'research',
      'title': '调研',
      'workspace': <String, Object?>{
        'root': root,
        'read': <String>['inbox'],
        'write': <String>['out'],
      },
      'inputs': <String>[],
      'prompt': '写报告',
      'network': 'deny',
      'expectedArtifacts': <String>[],
      'acceptance': <String>[],
      'limits': <String, Object?>{'maxMinutes': 20, 'maxCostUsd': 1.5},
      'checkpoint': <String, Object?>{'enabled': true, 'keep': 30},
    });

void main() {
  test('装配出 fs / tools / session / 检查点，并可释放', () async {
    final Directory tmp = Directory.systemTemp.createTempSync('assemble_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final WorkspacePlan workspace =
        await prepareWorkspace(task: card('work'), rootOverride: '${tmp.path}/work');
    expect(Directory('${tmp.path}/work/out').existsSync(), isTrue);

    final RunPaths paths =
        RunPaths(runsDir: '${tmp.path}/runs', runId: 'run_x');
    await paths.create();
    final RunScope scope = await assembleRun(
        task: card('work'), workspace: workspace, paths: paths);
    expect(scope.session.id, 'events');
    expect(scope.checkpoint.turn, 0);
    expect(scope.toolNames, containsAll(<String>['read', 'write', 'move', 'mkdir']));
    await expectLater(
        scope.fs.resolve('/etc/hosts').then((t) => scope.fs.readText(t)),
        throwsA(isA<FsError>()));
    await scope.dispose();
    expect(scope.ctx.disposed, isTrue);
  });

  test('工作区根按 cwd 解析，覆盖值不二次拼接', () {
    expect(resolveWorkspaceRoot(task: card('work'), cwd: '/base'), '/base/work');
    expect(
        resolveWorkspaceRoot(
            task: card('work'), rootOverride: 'rel/out', cwd: '/base'),
        '/base/rel/out');
    expect(
        resolveWorkspaceRoot(
            task: card('work'), rootOverride: '/abs/x', cwd: '/base'),
        '/abs/x');
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd products/conatus_work && dart test test/integration/assembly_test.dart`
Expected: FAIL

- [ ] **Step 3: 实现**

`prepareWorkspace`：`rootAbsolute = normalizeReadOnlyPath(rootOverride ?? task.workspaceRoot)`（相对路径按 `Directory.current` 解析；`rootOverride` 已是绝对路径时原样规范化），建根与每个 `write` 前缀目录，返回 `readPrefixes = read ∪ write`、`writePrefixes = write`。

`assembleRun` 按序：
1. `Context.root()`
2. `fs = RootedFileSystem(inner: LocalFileSystem(cwd: rootAbsolute), root: rootAbsolute, readPrefixes: workspace.readPrefixes, writePrefixes: workspace.writePrefixes)`
3. `provideFileSystemLocal(ctx, fs: fs)`
4. `provideTools(ctx)`；`provideFsTools(ctx, options: FsToolOptions(enablePatch: true, skipDirs: {...kDefaultSkipDirs, '.conatus_work'}))`；`ctx.tools.register(MkdirTool(fs: fs))`、`register(MoveTool(fs: fs))`
5. `sessionStore = provideSessions(ctx, sessions: SessionStore(persistence: JsonlSessionPersistence(dir: paths.runDir)))`；`session = await sessionStore.open('events')`（新运行目录里文件不存在，`open` 返回空会话，正好复用同一路径做 `resume`）
6. `options = CheckpointOptions(enabled: task.checkpointEnabled, keep: task.checkpointKeep, policy: productCheckpointPolicy())`；`store = await openCheckpointStore(options: options, root: rootAbsolute, projectDir: paths.runDir)`；`checkpoint = CheckpointManager(store: store, options: options)`；`await (fresh ? checkpoint.reset('events') : checkpoint.bind('events'))`；`await checkpoint.flush()`
7. `ctx.provide('checkpointManager', checkpoint)` 便于第 2 周 Agent Loop 取用
8. `toolNames = ctx.tools.names`

`dispose`：`sessionStore.close(session.id)` 后 `ctx.dispose()`。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd products/conatus_work && dart test test/integration/assembly_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
cd products/conatus_work
git add lib/src/runner/workspace.dart lib/src/runner/assembly.dart test/integration/assembly_test.dart
git commit -m "feat(runner): 工作区准备与 Context 装配"
```

---

### Task 7: `run` 编排、轮次边界与中断标志

**Files:**
- Create: `products/conatus_work/lib/src/runner/abort_signal.dart`
- Create: `products/conatus_work/lib/src/runner/runner.dart`
- Test: `products/conatus_work/test/integration/run_test.dart`

**Interfaces:**
- Consumes: Task 1/2/5/6 的全部产出
- Produces:
  - `class AbortSignal { AbortSignal(this.flagPath); final String flagPath; bool get requested; Future<void> request(); }`
  - `bool pidAlive(int pid)`
  - `class TaskOutcome { const TaskOutcome.ok(); const TaskOutcome.failed(FailureCategory category, String message); const TaskOutcome.aborted(); final RunStatus status; final RunFailure? failure; }`
  - `typedef TaskBody = Future<TaskOutcome> Function(RunScope scope, TaskSpec task);`
  - `TaskBody noopTaskBody`（第 1 周的默认执行体）
  - `class Runner { Runner({required this.body, this.runsDir = 'var/runs'}); final TaskBody body; final String runsDir; Future<RunRecord> run(TaskSpec task, {required String taskPath, String? workspaceRoot, String? rerunOf}); }`

- [ ] **Step 1: 写失败测试**

```dart
import 'dart:io';
import 'package:conatus/conatus.dart';
import 'package:conatus_work/src/runner/abort_signal.dart';
import 'package:conatus_work/src/runner/assembly.dart';
import 'package:conatus_work/src/runner/run_paths.dart';
import 'package:conatus_work/src/runner/run_store.dart';
import 'package:conatus_work/src/runner/runner.dart';
import 'package:conatus_work/src/runner/task_spec.dart';
import 'package:test/test.dart';

TaskSpec card({List<String> artifacts = const <String>[]}) =>
    TaskSpec.parse(<String, Object?>{
      'id': 'empty-v01',
      'chain': 'research',
      'title': '空任务',
      'workspace': <String, Object?>{
        'root': 'work',
        'read': <String>[],
        'write': <String>['out'],
      },
      'inputs': <String>[],
      'prompt': '空跑',
      'network': 'deny',
      'expectedArtifacts': artifacts,
      'acceptance': <String>[],
      'limits': <String, Object?>{'maxMinutes': 1, 'maxCostUsd': 0.1},
      'checkpoint': <String, Object?>{'enabled': true, 'keep': 30},
    });

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('run_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('空任务卡跑通，turns 0→1', () async {
    final Runner runner = Runner(body: noopTaskBody, runsDir: '${tmp.path}/runs');
    final RunRecord record = await runner.run(card(),
        taskPath: '${tmp.path}/empty.json', workspaceRoot: '${tmp.path}/work');
    expect(record.status, RunStatus.succeeded);
    expect(record.startTurn, 0);
    expect(record.endTurn, 1);
    expect(record.checkpointStatus, CheckpointStatus.ok);
    final RunRecord loaded = await RunStore(RunPaths(
            runsDir: '${tmp.path}/runs', runId: record.runId))
        .load();
    expect(loaded.status, RunStatus.succeeded);
  });

  test('期望产物缺失 → failed/artifact', () async {
    final Runner runner = Runner(body: noopTaskBody, runsDir: '${tmp.path}/runs');
    final RunRecord record = await runner.run(
        card(artifacts: <String>['out/report.md']),
        taskPath: '${tmp.path}/empty.json',
        workspaceRoot: '${tmp.path}/work');
    expect(record.status, RunStatus.failed);
    expect(record.failure.category, FailureCategory.artifact);
  });

  test('abort.request 在执行体结束后生效 → aborted', () async {
    final Runner runner = Runner(
      runsDir: '${tmp.path}/runs',
      body: (RunScope scope, TaskSpec task) async {
        await AbortSignal(scope.paths.abortFlagPath).request();
        return const TaskOutcome.ok();
      },
    );
    final RunRecord record = await runner.run(card(),
        taskPath: '${tmp.path}/empty.json', workspaceRoot: '${tmp.path}/work');
    expect(record.status, RunStatus.aborted);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd products/conatus_work && dart test test/integration/run_test.dart`
Expected: FAIL

- [ ] **Step 3: 实现**

`abort_signal.dart`：`requested` 判 `File(flagPath).existsSync()`；`request()` 建父目录并写空文件；`pidAlive(pid)` 用 `Process.runSync('kill', <String>['-0', '$pid']).exitCode == 0`。

`runner.run` 顺序：
1. `prepareWorkspace`
2. `runId = newRunId(DateTime.now())`；`paths.create()`
3. 先存一次 `RunRecord`：`status: running`、`pid: pid`、`taskPath: File(taskPath).absolute.path`、`tools: <空列表>`（装配后回填）
4. `prepareWorkspace(task: task, rootOverride: workspaceRoot)` → `assembleRun(fresh: true)` → 回填 `startTurn = checkpoint.turn`、`tools = scope.toolNames`、`sessionId`，`save`
5. `body(scope, task)`；执行前后都查 `AbortSignal(scope.paths.abortFlagPath).requested`，命中则 `status = aborted` 并跳过产物判定
6. `checkArtifacts(root: workspace.rootAbsolute, expected: task.expectedArtifacts)`；任一 `passed == false` → `failed` / `artifact`
7. 收口：`snapshotError = await checkpoint.recordTurn(lastEventId: scope.session.lastEventId)`；`applySnapshot(record, snapshotError)`；`endTurn = checkpoint.turn`
8. `endedAt = DateTime.now()`；`save`；`dispose`
9. 任何异常：`failure = internal`，仍然执行第 7 步收口，`dispose` 放在 `finally`；不向调用方重抛——返回 `failed` 记录并让 CLI 打日志。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd products/conatus_work && dart test test/integration/run_test.dart`
Expected: PASS（3 个测试）

- [ ] **Step 5: 提交**

```bash
cd products/conatus_work
git add lib/src/runner/abort_signal.dart lib/src/runner/runner.dart test/integration/run_test.dart
git commit -m "feat(runner): run 编排与轮次边界"
```

---

### Task 8: `resume` 与 `abort`

**Files:**
- Modify: `products/conatus_work/lib/src/runner/runner.dart`
- Test: `products/conatus_work/test/integration/resume_abort_test.dart`

**Interfaces:**
- Consumes: Task 7 的 `Runner` / `RunRecord`
- Produces: `Future<RunRecord> Runner.resume(String runId)`、`Future<RunRecord> Runner.abort(String runId)`

- [ ] **Step 1: 写失败测试**

```dart
import 'dart:convert';
import 'dart:io';
import 'package:conatus_work/src/runner/run_paths.dart';
import 'package:conatus_work/src/runner/run_store.dart';
import 'package:conatus_work/src/runner/runner.dart';
import 'package:conatus_work/src/runner/task_spec.dart';
import 'package:test/test.dart';

Map<String, Object?> cardJson() => <String, Object?>{
      'id': 'empty-v01', 'chain': 'research', 'title': '空任务',
      'workspace': <String, Object?>{'root': 'work', 'read': <String>[], 'write': <String>['out']},
      'inputs': <String>[], 'prompt': '空跑', 'network': 'deny',
      'expectedArtifacts': <String>[], 'acceptance': <String>[],
      'limits': <String, Object?>{'maxMinutes': 1, 'maxCostUsd': 0.1},
      'checkpoint': <String, Object?>{'enabled': true, 'keep': 30},
    };

void main() {
  late Directory tmp;
  late String cardPath;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('resume_');
    cardPath = '${tmp.path}/card.json';
    File(cardPath).writeAsStringSync(jsonEncode(cardJson()));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('执行体抛异常后 resume 续到下一轮', () async {
    bool first = true;
    final Runner runner = Runner(
      runsDir: '${tmp.path}/runs',
      body: (scope, task) async {
        if (first) {
          first = false;
          throw StateError('boom');
        }
        return const TaskOutcome.ok();
      },
    );
    final RunRecord firstRun = await runner.run(TaskSpec.parse(cardJson()),
        taskPath: cardPath, workspaceRoot: '${tmp.path}/work');
    expect(firstRun.status, RunStatus.failed);
    expect(firstRun.failure.category, FailureCategory.internal);
    final RunRecord resumed = await runner.resume(firstRun.runId);
    expect(resumed.status, RunStatus.succeeded);
    expect(resumed.startTurn, 1);
    expect(resumed.endTurn, 2);
    expect(resumed.resumeCount, 1);
  });

  test('abort 一个已死进程的 run：标 aborted 且收口', () async {
    final Runner runner = Runner(body: noopTaskBody, runsDir: '${tmp.path}/runs');
    final RunRecord record = await runner.run(TaskSpec.parse(cardJson()),
        taskPath: cardPath, workspaceRoot: '${tmp.path}/work');
    final RunStore store =
        RunStore(RunPaths(runsDir: runner.runsDir, runId: record.runId));
    final RunRecord dead = await store.load()
      ..status = RunStatus.running
      ..pid = 999999
      ..endedAt = null;
    await store.save(dead);
    final RunRecord aborted = await runner.abort(record.runId);
    expect(aborted.status, RunStatus.aborted);
    expect(aborted.checkpointStatus, CheckpointStatus.ok);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd products/conatus_work && dart test test/integration/resume_abort_test.dart`
Expected: FAIL（`resume` 未定义）

- [ ] **Step 3: 实现**

`resume`：`store.load()` → `TaskSpec.load(record.taskPath)` → `prepareWorkspace` → `assembleRun` 但走 `bind('events')` 而不是 `reset`（给 `assembleRun` 加 `bool fresh = true` 参数，`fresh: false` 时 `bind`）→ `record.startTurn = checkpoint.turn`、`record.pid = pid`、`record.status = running`、`resumeCount + 1`、`endedAt = null` → `save` → 执行体 → 产物校验 → `recordTurn` 收口。

`abort`：`store.load()`；`pidAlive(record.pid)` 时只写 `abort.request` 并返回记录（不改状态）；否则用 `TaskSpec.load(record.taskPath)` 取检查点选项，打开 store + `bind('events')` + `recordTurn`，标 `aborted`，`applySnapshot`，`endedAt = now`，`save`。

`resume` 的 `assembleRun` 用 `fresh: false`（`bind` 接管已有时间线），`prepareWorkspace(rootOverride: record.workspaceRoot)`——`run.json.workspaceRoot` 存绝对路径，因此换个 cwd 恢复也不会指错。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd products/conatus_work && dart test test/integration/resume_abort_test.dart`
Expected: PASS（2 个测试）

- [ ] **Step 5: 提交**

```bash
cd products/conatus_work
git add lib/src/runner/runner.dart test/integration/resume_abort_test.dart
git commit -m "feat(runner): resume 与 abort"
```

---

### Task 9: CLI、report、edit 与冒烟任务卡

**Files:**
- Create: `products/conatus_work/lib/src/runner/report.dart`
- Create: `products/conatus_work/lib/src/runner/cli.dart`
- Create: `products/conatus_work/bin/runner.dart`
- Create: `products/conatus_work/tasks/empty-smoke.json`
- Modify: `products/conatus_work/lib/conatus_work.dart`（导出公共 API）
- Modify: `products/conatus_work/README.md`（用法一节）
- Test: `products/conatus_work/test/unit/report_test.dart`

**Interfaces:**
- Consumes: Task 2 `RunRecord`、Task 7/8 `Runner`
- Produces:
  - `String renderReport(Iterable<RunRecord> records)`
  - `Future<int> runCli(List<String> args)`
  - `bin/runner.dart` 的 `main` 只做 `exitCode = await runCli(args);`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:conatus_work/src/runner/report.dart';
import 'package:conatus_work/src/runner/run_store.dart';
import 'package:test/test.dart';

RunRecord rec(String chain, RunStatus status, {bool edited = false}) => RunRecord(
      runId: 'r', taskId: 't', chain: chain, taskPath: '/t.json',
      workspaceRoot: 'w', sessionId: 'events', pid: 1,
      startedAt: DateTime(2026, 11, 2),
    )
      ..status = status
      ..humanEdits = edited
          ? <HumanEdit>[HumanEdit(at: DateTime(2026, 11, 2), artifact: 'out/a.md', note: 'n')]
          : <HumanEdit>[];

void main() {
  test('按链统计成功、失败与救场率', () {
    final String text = renderReport(<RunRecord>[
      rec('research', RunStatus.succeeded),
      rec('research', RunStatus.succeeded, edited: true),
      rec('csv', RunStatus.failed),
    ]);
    expect(text, contains('research'));
    expect(text, contains('2/2'));
    expect(text, contains('50.0%'));
    expect(text, contains('csv'));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd products/conatus_work && dart test test/unit/report_test.dart`
Expected: FAIL

- [ ] **Step 3: 实现**

`report.dart`：按 `chain` 分组，每行固定形状
`<chain>\ttotal=<n>\tsucceeded=<s>/<n>\tfailed=<f>\taborted=<a>\trescued=<r>\trescueRate=<p>%\tartifactRate=<q>%`，
末尾再来一行 `total` 汇总。救场 = `humanEdits` 非空或 `rerunOf` 非空；百分比保留一位小数。

`cli.dart`：手写解析，未知参数打印用法并返回 64。
- `list`：glob `tasks/*.json`，逐个 `TaskSpec.load`，打印 `id | chain | title | artifacts`
- `run <card> --workspace <dir> [--fixture <dir>] [--rerun-of <id>]`：`--workspace` 是**工作区根**，直接传给 `run(workspaceRoot:)` 覆盖任务卡的 `workspace.root`；不传时用任务卡的值。`taskPath` 传源文件的绝对路径；`--fixture` 第 1 周只打印「未实现」并返回 2
- `resume <runId>` / `abort <runId>`：`runsDir` 固定 `var/runs`
- `report [dir]`：读目录下每个子目录的 `run.json`，跳过坏文件，打印 `renderReport`
- `edit <runId> --artifact <rel> --note <text>`：`store.load()` → 若 `$workspaceRoot/$artifact` 存在则算 `sha256` → 追加 `HumanEdit(sha256: …)` → `save`
- 所有相对路径按 `Directory.current` 解析；摘要里打印绝对工作区根。

`tasks/empty-smoke.json`：

```json
{
  "id": "empty-smoke",
  "chain": "research",
  "title": "空任务冒烟",
  "workspace": { "root": "var/workspaces/smoke", "read": [], "write": ["out"] },
  "inputs": [],
  "prompt": "空跑，不做事",
  "network": "deny",
  "expectedArtifacts": [],
  "acceptance": [],
  "limits": { "maxMinutes": 1, "maxCostUsd": 0.1 },
  "checkpoint": { "enabled": true, "keep": 30 }
}
```

`lib/conatus_work.dart` 追加 `export 'src/runner/cli.dart' show runCli;` 与 `export 'src/runner/runner.dart'`。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd products/conatus_work && dart test test/unit/report_test.dart`
Expected: PASS

- [ ] **Step 5: 端到端冒烟（手动验证，必须真的执行）**

```bash
cd products/conatus_work
dart run bin/runner.dart run tasks/empty-smoke.json --workspace var/workspaces/smoke
cat var/runs/*/run.json
```

Expected：输出 `succeeded`；`run.json` 里 `status: "succeeded"`、`startTurn: 0`、`endTurn: 1`、`checkpointStatus: "ok"`、`artifacts: []`。

- [ ] **Step 6: 全仓静态检查与全量测试**

```bash
cd /Users/fitz/REPO/conatus
dart analyze --fatal-infos
cd products/conatus_work && dart test
```

Expected：analyze 无输出（0 issues）；测试全绿。

- [ ] **Step 7: 提交**

```bash
cd products/conatus_work
git add lib/src/runner/report.dart lib/src/runner/cli.dart bin/runner.dart \
  tasks/empty-smoke.json lib/conatus_work.dart README.md test/unit/report_test.dart
git commit -m "feat(runner): CLI、汇总与冒烟任务卡"
```

---

## 完成判据

- `dart analyze --fatal-infos` 全仓 0 issue。
- `cd products/conatus_work && dart test` 全绿（9 个测试文件）。
- `run tasks/empty-smoke.json` 产出 `status: succeeded`、`turns 0→1` 的 `run.json`。
- `RootedFileSystem` 测试覆盖：前缀歧义、`../`、符号链接逃逸、删根。
- 第 1 周不接 Agent Loop / shell / 模型，`run.json.model` 为 `null`。
