# nava 工具层安全护栏 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `packages/conatus_code` 内实现读后写守卫、重复调用熔断与敏感文件硬阻断，默认开启、可配置关闭，不修改父仓库包。

**Architecture:** 三项能力都实现为同步 `ToolGuard`（先于审批中间件执行，并被 `copyPipelineTo` 复制给子代理），读台账与重复计数由一条后置中间件维护。路径身份统一走 canonical 绝对路径；配置集中在新增 `[safety]` 表；会话切换时清空台账与计数。

**Tech Stack:** Dart 3.10+、`package:test`（手写 Fake / 临时目录，不用 mock 框架）、conatus `Context` / `ToolRegistry`、`conatus_fs_tools`。

**Spec:** `docs/superpowers/specs/2026-11-23-nava-tool-safety-guards-design.md`

## Global Constraints

- 只改 `packages/conatus_code`；不修改 `packages/conatus_agent` / `packages/conatus_foundation`。
- 守卫是同步的 `String? Function(ToolCall)`；不得引入异步守卫或修改 `ToolGuard` typedef。
- 稳定错误前缀（模型可见）：`WRITE_WITHOUT_READ:`、`WRITE_STALE_READ:`、`REPEAT_CALL_BLOCKED`、`SENSITIVE_PATH:`。
- 配置缺省：`require_read_before_write=true`、`repeat_warn_at=3`、`repeat_deny_at=5`、`protect_private_keys=true`、`deny_dotenv_writes=true`。
- 仓库硬约束：单文件 ≤ 200 行、单 class ≤ 150 行、函数体 ≤ 40 行、参数 ≤ 4 个、分支 ≤ 3、嵌套 ≤ 2；超出加 `// REASON:`。
- 包内用相对导入、单引号、`final` 局部变量、显式返回类型（`dart analyze --fatal-infos`）。
- 面向用户的文案用中文；配置键用 snake_case。
- 测试用真实临时目录 + `LocalFileSystem`，与 `test/fs_tools/` 现有风格一致。
- 每项功能独立可关；全关时现有测试与行为零变化。

## Review Focus

- **同一文件的多种拼写**（相对、`./`、`~`、绝对、符号链接）必须命中同一条台账记录；否则读后写守卫会误拒或漏放。
- **非文本读取**（目录列举、图片、PDF）的 `value` 没有 `version`，不能作为覆盖文本文件的授权。
- **`apply_patch` 两种格式**（unified / OpenCode `***`）里 Add 与 Update/Delete 的区分：Add 必须豁免先读，Update/Delete 必须要求先读。
- **会话生命周期**：切换会话清空台账；恢复旧会话首次修改应被要求重读；子代理与主代理共享台账。
- **敏感文件豁免**：`*.pub`、`.env.example/.sample/.template` 必须放行；Windows 分隔符与大小写不应导致漏挡或误挡。

---

### Task 1: 共享 canonical 路径解析

**Files:**
- Create: `packages/conatus_code/lib/src/paths/canonical_path.dart`
- Modify: `packages/conatus_code/lib/src/instructions/instruction_paths.dart`
- Test: `packages/conatus_code/test/paths/canonical_path_test.dart`

**Interfaces:**
- Produces:
  - `String expandToolHome(String value, String? home)`
  - `String canonicalizeBestEffortPath(String path)`
  - `String? canonicalToolPath(String workdir, String? home, String rawPath)`
- Consumes: 无（仅 `dart:io`）。

- [ ] **Step 1: 写失败测试**

```dart
// test/paths/canonical_path_test.dart
import 'dart:io';
import 'package:conatus_code/safety.dart';
import 'package:test/test.dart';

void main() {
  test('相对路径按 workdir 解析到真实文件', () {
    final Directory dir = Directory.systemTemp.createTempSync('nava-canon');
    addTearDown(() => dir.deleteSync(recursive: true));
    final File file = File('${dir.path}${Platform.pathSeparator}a.txt')
      ..writeAsStringSync('x');
    expect(
      canonicalToolPath(dir.path, null, './a.txt'),
      file.resolveSymbolicLinksSync(),
    );
  });

  test('~ 展开到 home；空串返回 null', () {
    final Directory dir = Directory.systemTemp.createTempSync('nava-home');
    addTearDown(() => dir.deleteSync(recursive: true));
    final File file = File('${dir.path}${Platform.pathSeparator}x.txt')
      ..writeAsStringSync('x');
    expect(
      canonicalToolPath(dir.path, dir.path, '~/x.txt'),
      file.resolveSymbolicLinksSync(),
    );
    expect(canonicalToolPath(dir.path, dir.path, '   '), isNull);
  });

  test('符号链接按真实目标返回', () {
    if (Platform.isWindows) return;
    final Directory dir = Directory.systemTemp.createTempSync('nava-link');
    addTearDown(() => dir.deleteSync(recursive: true));
    final File target = File('${dir.path}${Platform.pathSeparator}t.txt')
      ..writeAsStringSync('x');
    Link('${dir.path}${Platform.pathSeparator}alias.txt').createSync(target.path);
    expect(
      canonicalToolPath(dir.path, null, 'alias.txt'),
      target.resolveSymbolicLinksSync(),
    );
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd packages/conatus_code && dart test test/paths/canonical_path_test.dart -r expanded`
Expected: FAIL — `safety.dart` 不存在 / `canonicalToolPath` 未定义。

- [ ] **Step 3: 实现共享模块并让指令层委托**

把 `instruction_paths.dart` 的 `expandInstructionHome`、`canonicalizeBestEffort`、
`resolveInstructionTargetPath` 实现搬到新文件并改名（`expandToolHome` /
`canonicalizeBestEffortPath` / `canonicalToolPath`），逻辑逐行不变。原函数改为：

```dart
String expandInstructionHome(String value, String? home) =>
    expandToolHome(value, home);

String canonicalizeBestEffort(String path) => canonicalizeBestEffortPath(path);

String? resolveInstructionTargetPath(String workdir, String? home, String rawPath) =>
    canonicalToolPath(workdir, home, rawPath);
```

新建 `lib/safety.dart`：

```dart
/// nava 工具层安全护栏：读后写 / 重复调用 / 敏感文件。
library;

export 'src/paths/canonical_path.dart'
    show canonicalToolPath, canonicalizeBestEffortPath, expandToolHome;
```

- [ ] **Step 4: 运行测试与指令层回归**

Run: `cd packages/conatus_code && dart test test/paths/canonical_path_test.dart test/instructions -r expanded`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/src/paths/canonical_path.dart lib/src/instructions/instruction_paths.dart lib/safety.dart test/paths/canonical_path_test.dart
git commit -m "refactor(safety): 抽出共享 canonical 路径解析"
```

---

### Task 2: `[safety]` 配置

**Files:**
- Modify: `packages/conatus_code/lib/src/config/config_schema.dart`（`ConatusCodeConfig` 约 584 行）
- Modify: `packages/conatus_code/lib/src/config/config_parser.dart`（`parse()` 约 36 行、新增 `_readSafety`）
- Modify: `packages/conatus_code/lib/src/config/config_loader.dart`（模板约 146 行 hooks 段后）
- Modify: `packages/conatus_code/lib/conatus_code.dart`（`config_schema` 的 `show` 列表约 138 行）
- Test: `packages/conatus_code/test/config/config_safety_test.dart`

**Interfaces:**
- Produces: `class SafetyConfig`，字段 `requireReadBeforeWrite` / `repeatWarnAt` / `repeatDenyAt` / `repeatExemptTools` / `protectPrivateKeys` / `denyDotenvWrites` / `extraSensitivePaths`；`ConatusCodeConfig.safety`。
- Consumes: `ConfigValues.readBool/readNonNegativeInt/readStringList/readTable`。

- [ ] **Step 1: 写失败测试**

```dart
// test/config/config_safety_test.dart
import 'dart:io';
import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

String _toml(String body) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-safety-cfg');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File file = File('${dir.path}${Platform.pathSeparator}$kConfigFileName')
    ..writeAsStringSync(body);
  return file.path;
}

void main() {
  test('缺省值', () {
    final ConatusCodeConfig c = loadConfig(path: _toml('[agent]\n'));
    expect(c.safety.requireReadBeforeWrite, isTrue);
    expect(c.safety.repeatWarnAt, 3);
    expect(c.safety.repeatDenyAt, 5);
    expect(c.safety.protectPrivateKeys, isTrue);
    expect(c.safety.denyDotenvWrites, isTrue);
    expect(c.safety.repeatExemptTools, isEmpty);
  });

  test('完整解析', () {
    final ConatusCodeConfig c = loadConfig(path: _toml('''
[safety]
require_read_before_write = false
repeat_warn_at = 2
repeat_deny_at = 4
repeat_exempt_tools = ["bash"]
protect_private_keys = false
deny_dotenv_writes = false
extra_sensitive_paths = ["secrets"]
'''));
    expect(c.safety.requireReadBeforeWrite, isFalse);
    expect(c.safety.repeatWarnAt, 2);
    expect(c.safety.repeatDenyAt, 4);
    expect(c.safety.repeatExemptTools, <String>['bash']);
    expect(c.safety.extraSensitivePaths, <String>['secrets']);
  });

  test('deny <= warn 报错；负数报错', () {
    expect(
      () => loadConfig(path: _toml('[safety]\nrepeat_warn_at = 5\nrepeat_deny_at = 3\n')),
      throwsA(isA<ConfigException>()),
    );
    expect(
      () => loadConfig(path: _toml('[safety]\nrepeat_deny_at = -1\n')),
      throwsA(isA<ConfigException>()),
    );
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd packages/conatus_code && dart test test/config/config_safety_test.dart -r expanded`
Expected: FAIL — `safety` getter 不存在。

- [ ] **Step 3: 实现配置**

在 `config_schema.dart` 加 `SafetyConfig`（含 `///` 注释，说明每项默认值与关闭方式），
`ConatusCodeConfig` 增加 `this.safety = const SafetyConfig()` 与字段；在
`lib/conatus_code.dart` 的 `config_schema` `show` 列表加入 `SafetyConfig`。解析器：

```dart
SafetyConfig _readSafety() {
  final Map<String, dynamic> table = readTable('safety');
  final int warn = readNonNegativeInt(table, 'repeat_warn_at', 3);
  final int deny = readNonNegativeInt(table, 'repeat_deny_at', 5);
  if (warn > 0 && deny > 0 && deny <= warn) {
    throw ConfigException('$source：safety.repeat_deny_at 必须大于 repeat_warn_at。');
  }
  return SafetyConfig(
    requireReadBeforeWrite: readBool(table, 'require_read_before_write', true),
    repeatWarnAt: warn,
    repeatDenyAt: deny,
    repeatExemptTools: readStringList(table, 'repeat_exempt_tools'),
    protectPrivateKeys: readBool(table, 'protect_private_keys', true),
    denyDotenvWrites: readBool(table, 'deny_dotenv_writes', true),
    extraSensitivePaths: readStringList(table, 'extra_sensitive_paths'),
  );
}
```

模板 `kDefaultConfigToml` 在 hooks 段后追加：

```toml
# 工具层安全护栏：读后写 / 重复调用熔断 / 敏感文件硬阻断。
[safety]
require_read_before_write = true   # 覆盖已有文件前必须先 read 且未被外部改动
repeat_warn_at = 3                 # 连续相同调用第 N 次起附加告警（0 关闭）
repeat_deny_at = 5                 # 连续相同调用第 N 次起拒绝执行（0 关闭）
# repeat_exempt_tools = ["bash"]   # 豁免轮询类命令
protect_private_keys = true        # 私钥 / 凭据硬拒
deny_dotenv_writes = true          # .env 族写入硬拒（读仍走权限 ask）
# extra_sensitive_paths = ["secrets"]
```

- [ ] **Step 4: 运行测试与配置回归**

Run: `cd packages/conatus_code && dart test test/config -r expanded`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/src/config test/config/config_safety_test.dart
git commit -m "feat(config): 新增 [safety] 护栏配置"
```

---

### Task 3: 补丁路径抽取

**Files:**
- Create: `packages/conatus_code/lib/src/safety/patch_paths.dart`
- Test: `packages/conatus_code/test/safety/patch_paths_test.dart`

**Interfaces:**
- Produces:
  - `class PatchTarget { const PatchTarget({required this.path, this.creates = false}); final String path; final bool creates; }`
  - `List<PatchTarget> patchTargets(String patch)`
- Consumes: 无。

- [ ] **Step 1: 写失败测试**

```dart
// test/safety/patch_paths_test.dart
import 'package:conatus_code/safety.dart';
import 'package:test/test.dart';

void main() {
  test('unified 更新两个文件', () {
    final List<PatchTarget> targets = patchTargets('''
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1 +1 @@
-a
+b
--- a/lib/b.dart
+++ b/lib/b.dart
''');
    expect(targets.map((PatchTarget t) => t.path), <String>['lib/a.dart', 'lib/b.dart']);
    expect(targets.every((PatchTarget t) => !t.creates), isTrue);
  });

  test('unified 新建 / 删除', () {
    final List<PatchTarget> added = patchTargets('--- /dev/null\n+++ b/new.txt\n');
    expect(added.single.creates, isTrue);
    final List<PatchTarget> deleted = patchTargets('--- a/old.txt\n+++ /dev/null\n');
    expect(deleted.single.path, 'old.txt');
    expect(deleted.single.creates, isFalse);
  });

  test('OpenCode 三种标记', () {
    final List<PatchTarget> targets = patchTargets('''
*** Begin Patch
*** Add File: a.txt
+x
*** Update File: b.txt
@@
*** Delete File: c.txt
*** End Patch
''');
    expect(targets.map((PatchTarget t) => t.path), <String>['a.txt', 'b.txt', 'c.txt']);
    expect(targets.first.creates, isTrue);
  });

  test('无法识别时返回空列表', () {
    expect(patchTargets('not a patch'), isEmpty);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd packages/conatus_code && dart test test/safety/patch_paths_test.dart -r expanded`
Expected: FAIL — `PatchTarget` / `patchTargets` 未定义。

- [ ] **Step 3: 实现解析器**

按行扫描：记录最近一条 `--- ` 作为 pending old；遇到 `+++ ` 时：
`+++ /dev/null` → 目标取 pending old（删除）；`pending old == /dev/null` → 新建；
其余 → 更新。OpenCode 行 `*** Add File:` / `*** Update File:` / `*** Delete File:`
直接映射。路径去引号、去 `a/`/`b/` 前缀，按路径去重（`creates=false` 优先）。
解析不到任何路径返回空列表。

在 `lib/safety.dart` 增加：

```dart
export 'src/safety/patch_paths.dart' show PatchTarget, patchTargets;
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd packages/conatus_code && dart test test/safety/patch_paths_test.dart -r expanded`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/src/safety/patch_paths.dart lib/safety.dart test/safety/patch_paths_test.dart
git commit -m "feat(safety): 抽取补丁目标路径（unified / OpenCode）"
```

---

### Task 4: 读台账与后置中间件

**Files:**
- Create: `packages/conatus_code/lib/src/safety/read_ledger.dart`
- Test: `packages/conatus_code/test/safety/read_ledger_test.dart`

**Interfaces:**
- Produces:
  - `String? fileFingerprint(String canonicalPath)` — 缺失/不可读返回 `null`，否则 `changed:modified:size`。
  - `class ReadLedger`：`int get length`、`String? fingerprintOf(String canonicalPath)`、`void note(String, String)`、`void forget(String)`、`void clear()`。
  - `class ReadLedgerMiddleware`：构造 `({required ReadLedger ledger, required String workdir, String? home})`，方法 `Future<ToolResult> call(ToolCall call, Future<ToolResult> Function() next)`。
- Consumes: Task 1 `canonicalToolPath`、Task 3 `patchTargets`。

- [ ] **Step 1: 写失败测试**

```dart
// test/safety/read_ledger_test.dart
import 'dart:io';
import 'package:conatus_code/safety.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

class _ReadTool extends Tool {
  const _ReadTool({this.withVersion = true});
  final bool withVersion;
  @override
  String get name => 'read';
  @override
  List<ParamSpec> get params => <ParamSpec>[ParamSpec.string('path', required: true)];
  @override
  Future<ToolResult> call(ToolContext ctx) async => ToolResult.success(
        'body',
        value: <String, Object?>{
          'path': ctx.str('path'),
          if (withVersion) 'version': 'v1',
        },
      );
}

void main() {
  late Directory dir;
  late LocalFileSystem fs;
  late ReadLedger ledger;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nava-ledger');
    fs = LocalFileSystem(cwd: dir.path);
    ledger = ReadLedger();
    File('${dir.path}${Platform.pathSeparator}a.txt').writeAsStringSync('x');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('read 成功后登记 canonical 路径指纹', () async {
    final ToolRegistry tools = ToolRegistry()..register(const _ReadTool());
    tools.use(ReadLedgerMiddleware(ledger: ledger, workdir: dir.path).call);
    await tools.call(const ToolCall(name: 'read', arguments: <String, Object?>{'path': 'a.txt'}));
    final String key = canonicalToolPath(dir.path, null, 'a.txt')!;
    expect(ledger.length, 1);
    expect(ledger.fingerprintOf(key), isNotNull);
  });

  test('无 version 的读取不登记', () async {
    final ToolRegistry tools = ToolRegistry()..register(const _ReadTool(withVersion: false));
    tools.use(ReadLedgerMiddleware(ledger: ledger, workdir: dir.path).call);
    await tools.call(const ToolCall(name: 'read', arguments: <String, Object?>{'path': 'a.txt'}));
    expect(ledger.length, 0);
  });

  test('失败的读取不登记', () async {
    final ToolRegistry tools = ToolRegistry()..register(const _FailingReadTool());
    tools.use(ReadLedgerMiddleware(ledger: ledger, workdir: dir.path).call);
    await tools.call(const ToolCall(name: 'read', arguments: <String, Object?>{'path': 'a.txt'}));
    expect(ledger.length, 0);
  });

  test('fileFingerprint 随文件内容变化', () {
    final String key = canonicalToolPath(dir.path, null, 'a.txt')!;
    final String? before = fileFingerprint(key);
    File(key).writeAsStringSync('changed content');
    expect(fileFingerprint(key), isNot(before));
    expect(fileFingerprint('${dir.path}${Platform.pathSeparator}missing.txt'), isNull);
  });
}

class _FailingReadTool extends Tool {
  const _FailingReadTool();
  @override
  String get name => 'read';
  @override
  List<ParamSpec> get params => <ParamSpec>[ParamSpec.string('path', required: true)];
  @override
  Future<ToolResult> call(ToolContext ctx) async =>
      ToolResult.failure('boom', error: const ToolError('FS_NOT_FOUND', 'boom'));
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd packages/conatus_code && dart test test/safety/read_ledger_test.dart -r expanded`
Expected: FAIL — `ReadLedger` / `fileFingerprint` 未定义。

- [ ] **Step 3: 实现台账与中间件**

`fileFingerprint` 用 `FileStat.statSync`；`notFound` 或异常返回 `null`；指纹格式
`'${changed.microsecondsSinceEpoch}:${modified.microsecondsSinceEpoch}:${size}'`。
中间件 `await next()` 后：失败直接返回；`read` 且 `value['path']`、`value['version']`
均为 `String` 时，canonical 化后 `note`；`write`/`edit` 成功时对 `path` 重新取指纹
（`null` 则 `forget`）；`apply_patch` 成功时对 `patchTargets` 逐个刷新。所有台账操作
包在 `try/catch` 内，异常不得影响工具结果。

`lib/safety.dart` 增加：

```dart
export 'src/safety/read_ledger.dart' show ReadLedger, ReadLedgerMiddleware, fileFingerprint;
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd packages/conatus_code && dart test test/safety/read_ledger_test.dart -r expanded`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/src/safety/read_ledger.dart lib/safety.dart test/safety/read_ledger_test.dart
git commit -m "feat(safety): 读台账与读写指纹维护"
```

---

### Task 5: 读后写守卫

**Files:**
- Create: `packages/conatus_code/lib/src/safety/write_guard.dart`
- Test: `packages/conatus_code/test/safety/write_guard_test.dart`

**Interfaces:**
- Produces:
  - `const String kWriteWithoutReadCode = 'WRITE_WITHOUT_READ';`
  - `const String kWriteStaleReadCode = 'WRITE_STALE_READ';`
  - `class ReadBeforeWriteGuard { ReadBeforeWriteGuard({required ReadLedger ledger, required String workdir, String? home, Set<String> toolNames = const <String>{'write', 'edit', 'apply_patch'}}); String? check(ToolCall call); }`
- Consumes: Task 1 `canonicalToolPath`、Task 3 `patchTargets`、Task 4 `ReadLedger` / `fileFingerprint`。

- [ ] **Step 1: 写失败测试**

```dart
// test/safety/write_guard_test.dart
import 'dart:io';
import 'package:conatus_code/safety.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late ReadLedger ledger;
  late ReadBeforeWriteGuard guard;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nava-write-guard');
    file = File('${dir.path}${Platform.pathSeparator}a.txt')..writeAsStringSync('old');
    ledger = ReadLedger();
    guard = ReadBeforeWriteGuard(ledger: ledger, workdir: dir.path);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ToolCall write(String path) => ToolCall(name: 'write', arguments: <String, Object?>{'path': path});

  test('未读覆盖已有文件被拒', () {
    expect(guard.check(write('a.txt')), startsWith('WRITE_WITHOUT_READ:'));
  });

  test('读过且未变化放行；变化后拒绝', () {
    final String key = canonicalToolPath(dir.path, null, 'a.txt')!;
    ledger.note(key, fileFingerprint(key)!);
    expect(guard.check(write('a.txt')), isNull);
    File(key).writeAsStringSync('changed');
    expect(guard.check(write('./a.txt')), startsWith('WRITE_STALE_READ:'));
  });

  test('新建文件放行；其他工具放行', () {
    expect(guard.check(write('new.txt')), isNull);
    expect(guard.check(const ToolCall(name: 'read', arguments: <String, Object?>{'path': 'a.txt'})), isNull);
  });

  test('apply_patch：Add 放行，Update 未读拒绝', () {
    expect(guard.check(const ToolCall(name: 'apply_patch', arguments: <String, Object?>{
      'patch': '*** Begin Patch\n*** Add File: new.txt\n+x\n*** End Patch',
    })), isNull);
    expect(guard.check(const ToolCall(name: 'apply_patch', arguments: <String, Object?>{
      'patch': '--- a/a.txt\n+++ b/a.txt\n',
    })), startsWith('WRITE_WITHOUT_READ:'));
  });

  test('符号链接别名命中同一台账', () {
    if (Platform.isWindows) return;
    Link('${dir.path}${Platform.pathSeparator}alias.txt').createSync(file.path);
    final String key = canonicalToolPath(dir.path, null, 'a.txt')!;
    ledger.note(key, fileFingerprint(key)!);
    expect(guard.check(write('alias.txt')), isNull);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd packages/conatus_code && dart test test/safety/write_guard_test.dart -r expanded`
Expected: FAIL — `ReadBeforeWriteGuard` 未定义。

- [ ] **Step 3: 实现守卫**

`check` 对 `write`/`edit` 取 `arguments['path']`（非 `String` 跳过），对
`apply_patch` 取 `arguments['patch']` 并调用 `patchTargets`（空列表放行）。每个目标：
`creates` 跳过；canonical 为 `null` 跳过；`fileFingerprint` 为 `null`（不存在）跳过；
台账无记录 → `WRITE_WITHOUT_READ: 覆盖已有文件前必须先读取：<path>（请先调用 read）`；
指纹不等 → `WRITE_STALE_READ: 文件自上次读取后已被修改：<path>（请重新 read）`。
多个目标任一失败即返回该条。

`lib/safety.dart` 增加：

```dart
export 'src/safety/write_guard.dart'
    show ReadBeforeWriteGuard, kWriteWithoutReadCode, kWriteStaleReadCode;
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd packages/conatus_code && dart test test/safety/write_guard_test.dart -r expanded`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/src/safety/write_guard.dart lib/safety.dart test/safety/write_guard_test.dart
git commit -m "feat(safety): 读后写守卫"
```

---

### Task 6: 重复调用熔断

**Files:**
- Create: `packages/conatus_code/lib/src/safety/repeat_breaker.dart`
- Test: `packages/conatus_code/test/safety/repeat_breaker_test.dart`

**Interfaces:**
- Produces:
  - `const String kRepeatBlockedCode = 'REPEAT_CALL_BLOCKED';`
  - `String callSignature(ToolCall call)`
  - `class RepeatTracker { RepeatTracker({this.warnAt = 3, this.denyAt = 5, this.exemptTools = const <String>{}}); final int warnAt; final int denyAt; final Set<String> exemptTools; int get count; String? check(ToolCall call); bool isCurrent(ToolCall call); void reset(); }`
  - `class RepeatWarning { RepeatWarning({required RepeatTracker tracker}); Future<ToolResult> call(ToolCall call, Future<ToolResult> Function() next); }`
- Consumes: `conatus_foundation` 的 `Tool` / `ToolRegistry` / `ToolResult`。

- [ ] **Step 1: 写失败测试**

```dart
// test/safety/repeat_breaker_test.dart
import 'package:conatus_code/safety.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

class _CountingTool extends Tool {
  int runs = 0;
  @override
  String get name => 'probe';
  @override
  Future<ToolResult> call(ToolContext ctx) async {
    runs++;
    return ToolResult.success('ok');
  }
}

void main() {
  const ToolCall call = ToolCall(name: 'probe', arguments: <String, Object?>{'a': 1, 'b': 2});

  test('3 次告警、5 次拒绝，不同调用清零', () async {
    final _CountingTool tool = _CountingTool();
    final ToolRegistry tools = ToolRegistry()..register(tool);
    final RepeatTracker tracker = RepeatTracker();
    tools.guard(tracker.check);
    tools.use(RepeatWarning(tracker: tracker).call);

    for (int i = 0; i < 2; i++) {
      final ToolResult r = await tools.call(call);
      expect(r.isError, isFalse);
      expect(r.content, isNot(contains('repeat-breaker')));
    }
    final ToolResult third = await tools.call(call);
    expect(third.content, contains('repeat-breaker'));
    expect(tool.runs, 3);

    final ToolResult fourth = await tools.call(call);
    expect(fourth.content, contains('repeat-breaker'));
    final ToolResult fifth = await tools.call(call);
    expect(fifth.isError, isTrue);
    expect(fifth.content, startsWith('REPEAT_CALL_BLOCKED'));
    expect(tool.runs, 4);

    await tools.call(const ToolCall(name: 'probe', arguments: <String, Object?>{'a': 9}));
    expect(tracker.count, 1);
  });

  test('参数键顺序不影响签名', () {
    final RepeatTracker tracker = RepeatTracker();
    expect(tracker.check(const ToolCall(name: 'probe', arguments: <String, Object?>{'a': 1, 'b': 2})), isNull);
    expect(tracker.check(const ToolCall(name: 'probe', arguments: <String, Object?>{'b': 2, 'a': 1})), isNull);
    expect(tracker.count, 2);
  });

  test('豁免工具不计数', () {
    final RepeatTracker tracker = RepeatTracker(exemptTools: const <String>{'bash'});
    for (int i = 0; i < 6; i++) {
      expect(tracker.check(const ToolCall(name: 'bash', arguments: <String, Object?>{'command': 'ls'})), isNull);
    }
  });

  test('阈值 0 关闭对应行为', () async {
    final _CountingTool tool = _CountingTool();
    final ToolRegistry tools = ToolRegistry()..register(tool);
    final RepeatTracker tracker = RepeatTracker(warnAt: 0, denyAt: 0);
    tools.guard(tracker.check);
    tools.use(RepeatWarning(tracker: tracker).call);
    for (int i = 0; i < 6; i++) {
      final ToolResult r = await tools.call(call);
      expect(r.isError, isFalse);
      expect(r.content, isNot(contains('repeat-breaker')));
    }
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd packages/conatus_code && dart test test/safety/repeat_breaker_test.dart -r expanded`
Expected: FAIL — `RepeatTracker` 未定义。

- [ ] **Step 3: 实现签名与状态机**

`callSignature`：按参数键排序后 `jsonEncode`，整串做 FNV-1a 64 位十六进制哈希，
返回 `'${call.name}\u0000$hash'`。`check`：豁免工具先 `reset` 返回 `null`；签名不同
重置为 1；相同则自增；`denyAt > 0 && count >= denyAt` 时返回
`'REPEAT_CALL_BLOCKED: 连续第 $count 次相同调用（${call.name}）；请换方法或汇报结论'`。
`RepeatWarning` 在 `next()` 后、`tracker.isCurrent(call)` 且
`warnAt > 0 && count >= warnAt && (denyAt == 0 || count < denyAt)` 时用
`result.withContent('${result.content}\n\n[repeat-breaker] 这是连续第 $count 次完全相同的调用；请换方法或汇报结论。')`。

`lib/safety.dart` 增加：

```dart
export 'src/safety/repeat_breaker.dart'
    show RepeatTracker, RepeatWarning, callSignature, kRepeatBlockedCode;
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd packages/conatus_code && dart test test/safety/repeat_breaker_test.dart -r expanded`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/src/safety/repeat_breaker.dart lib/safety.dart test/safety/repeat_breaker_test.dart
git commit -m "feat(safety): 重复调用熔断"
```

---

### Task 7: 敏感文件规则与守卫

**Files:**
- Create: `packages/conatus_code/lib/src/safety/sensitive_paths.dart`
- Create: `packages/conatus_code/lib/src/safety/sensitive_guard.dart`
- Test: `packages/conatus_code/test/safety/sensitive_paths_test.dart`
- Test: `packages/conatus_code/test/safety/sensitive_guard_test.dart`

**Interfaces:**
- Produces:
  - `enum SensitiveKind { dotenv, privateKey, credentials, extra }`
  - `class SensitiveMatch { const SensitiveMatch(this.kind, this.path); final SensitiveKind kind; final String path; }`
  - `SensitiveMatch? matchSensitivePath(String path, {Set<String> extraPaths = const <String>{}})`
  - `String sensitiveMessage(SensitiveMatch match)`
  - `class SensitivePathGuard { SensitivePathGuard({required ToolRegistry tools, required String workdir, String? home, bool protectPrivateKeys = true, bool denyDotenvWrites = true, Set<String> extraPaths = const <String>{}}); String? check(ToolCall call); }`
- Consumes: Task 1 `canonicalToolPath`、Task 3 `patchTargets`。

- [ ] **Step 1: 写失败测试（规则表）**

```dart
// test/safety/sensitive_paths_test.dart
import 'package:conatus_code/safety.dart';
import 'package:test/test.dart';

void main() {
  test('私钥命中与变体', () {
    for (final String p in <String>[
      '/home/u/.ssh/id_rsa',
      '/home/u/.ssh/id_ed25519',
      '/home/u/.ssh/id_rsa.bak',
      '/home/u/.ssh/id_rsa_old',
      '/home/u/.ssh/id_rsa-copy',
    ]) {
      expect(matchSensitivePath(p)?.kind, SensitiveKind.privateKey, reason: p);
    }
  });

  test('公钥与 .env 豁免放行', () {
    expect(matchSensitivePath('/home/u/.ssh/id_rsa.pub'), isNull);
    expect(matchSensitivePath('/work/.env.example'), isNull);
    expect(matchSensitivePath('/work/.env.sample'), isNull);
  });

  test('凭据与 .env 族', () {
    expect(matchSensitivePath('/work/credentials')?.kind, SensitiveKind.credentials);
    expect(matchSensitivePath('/home/u/.aws/credentials')?.kind, SensitiveKind.credentials);
    expect(matchSensitivePath('/home/u/.gcp/credentials')?.kind, SensitiveKind.credentials);
    expect(matchSensitivePath('/work/.env')?.kind, SensitiveKind.dotenv);
    expect(matchSensitivePath('/work/.env.local')?.kind, SensitiveKind.dotenv);
  });

  test('Windows 分隔符与大小写', () {
    expect(matchSensitivePath(r'C:\Users\u\.ssh\ID_RSA')?.kind, SensitiveKind.privateKey);
    expect(matchSensitivePath(r'C:\work\.ENV')?.kind, SensitiveKind.dotenv);
  });

  test('extraPaths 支持名称与路径段', () {
    expect(matchSensitivePath('/work/secrets/token.txt', extraPaths: <String>{'secrets'})?.kind, SensitiveKind.extra);
    expect(matchSensitivePath('/work/token.txt', extraPaths: <String>{'token.txt'})?.kind, SensitiveKind.extra);
  });
}
```

- [ ] **Step 2: 写失败测试（守卫）**

```dart
// test/safety/sensitive_guard_test.dart
import 'dart:io';
import 'package:conatus_code/safety.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

class _PathTool extends Tool {
  const _PathTool(this.name);
  @override
  final String name;
  @override
  List<String> get pathParams => const <String>['path'];
  @override
  Future<ToolResult> call(ToolContext ctx) async => ToolResult.success('ok');
}

class _BashTool extends Tool {
  const _BashTool();
  @override
  String get name => 'bash';
  @override
  Future<ToolResult> call(ToolContext ctx) async => ToolResult.success('ok');
}

class _PatchTool extends Tool {
  const _PatchTool();
  @override
  String get name => 'apply_patch';
  @override
  Future<ToolResult> call(ToolContext ctx) async => ToolResult.success('ok');
}

void main() {
  late Directory home;
  late ToolRegistry tools;
  late SensitivePathGuard guard;

  setUp(() {
    home = Directory.systemTemp.createTempSync('nava-sensitive');
    tools = ToolRegistry()
      ..register(const _PathTool('read'))
      ..register(const _PathTool('write'))
      ..register(const _BashTool())
      ..register(const _PatchTool());
    guard = SensitivePathGuard(tools: tools, workdir: home.path, home: home.path);
  });
  tearDown(() => home.deleteSync(recursive: true));

  ToolCall call(String tool, String path) =>
      ToolCall(name: tool, arguments: <String, Object?>{'path': path});

  test('私钥读写拒绝；.env 读放行、写拒绝', () {
    expect(guard.check(call('read', '~/.ssh/id_rsa')), startsWith('SENSITIVE_PATH:'));
    expect(guard.check(call('write', '~/.ssh/id_rsa')), startsWith('SENSITIVE_PATH:'));
    expect(guard.check(call('read', '.env')), isNull);
    expect(guard.check(call('write', '.env')), startsWith('SENSITIVE_PATH:'));
  });

  test('denyDotenvWrites=false 时 .env 写放行', () {
    final SensitivePathGuard relaxed = SensitivePathGuard(
      tools: tools,
      workdir: home.path,
      home: home.path,
      denyDotenvWrites: false,
    );
    expect(relaxed.check(call('write', '.env')), isNull);
  });

  test('bash 字面私钥路径拒绝；普通命令放行', () {
    expect(
      guard.check(const ToolCall(name: 'bash', arguments: <String, Object?>{'command': 'cat ~/.ssh/id_rsa'})),
      startsWith('SENSITIVE_PATH:'),
    );
    expect(
      guard.check(const ToolCall(name: 'bash', arguments: <String, Object?>{'command': 'echo hi > out.txt'})),
      isNull,
    );
  });

  test('apply_patch 命中凭据路径拒绝', () {
    expect(
      guard.check(const ToolCall(name: 'apply_patch', arguments: <String, Object?>{
        'patch': '*** Begin Patch\n*** Update File: credentials\n+x\n*** End Patch',
      })),
      startsWith('SENSITIVE_PATH:'),
    );
  });

  test('protectPrivateKeys=false 关闭私钥阻断', () {
    final SensitivePathGuard relaxed = SensitivePathGuard(
      tools: tools,
      workdir: home.path,
      home: home.path,
      protectPrivateKeys: false,
    );
    expect(relaxed.check(call('read', '~/.ssh/id_rsa')), isNull);
  });
}
```

- [ ] **Step 3: 运行测试确认失败**

Run: `cd packages/conatus_code && dart test test/safety/sensitive_paths_test.dart test/safety/sensitive_guard_test.dart -r expanded`
Expected: FAIL — 类型与函数未定义。

- [ ] **Step 4: 实现规则与守卫**

规则：路径先统一 `/`、小写；先判豁免（`*.pub`、`.env.example|.sample|.template`），
再判 `.aws/credentials` / `.gcp/credentials` 后缀、`credentials` 名称、私钥名称及
`-` / `_` / `.` 变体，最后判 `.env` 族。`extraPaths` 含分隔符按路径段后缀匹配，
否则按 basename 精确匹配。

守卫：`protectPrivateKeys=false && denyDotenvWrites=false && extraPaths.isEmpty`
直接返回 `null`；从 `tools.get(call.name)?.pathParams` 取路径参数（非 `String` 跳过）；
`bash` 扫 `command` 的字面 token（按空白与 `"'`|&;<>()` 切分）；`apply_patch` 扫
`patchTargets`。私钥/凭据/extra 一律拒绝；`.env` 仅对 `write`/`edit`/`apply_patch`
且 `denyDotenvWrites=true` 拒绝（`bash` 的 `.env` 字面量不拦，保持读 ask 语义）。
canonical 解析失败（如无 `home` 时的 `~`）退回原路径做段级匹配。
消息：`SENSITIVE_PATH: 拒绝访问<私钥文件|凭据文件|敏感路径|.env 写入> "<path>"`。

`lib/safety.dart` 增加：

```dart
export 'src/safety/sensitive_paths.dart'
    show SensitiveKind, SensitiveMatch, matchSensitivePath, sensitiveMessage;
export 'src/safety/sensitive_guard.dart' show SensitivePathGuard;
```

- [ ] **Step 5: 运行测试确认通过**

Run: `cd packages/conatus_code && dart test test/safety/sensitive_paths_test.dart test/safety/sensitive_guard_test.dart -r expanded`
Expected: PASS。

- [ ] **Step 6: 提交**

```bash
git add lib/src/safety/sensitive_paths.dart lib/src/safety/sensitive_guard.dart lib/safety.dart test/safety
git commit -m "feat(safety): 敏感文件硬阻断"
```

---

### Task 8: 装配、会话复位与文档

**Files:**
- Create: `packages/conatus_code/lib/src/safety/safety_assembly.dart`
- Modify: `packages/conatus_code/lib/safety.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_app.dart`（`provideTools` 约 331 行后；`create` 参数表约 274 行）
- Modify: `packages/conatus_code/lib/src/tui/tui_controller.dart`（`_bind` 约 4133 行、`_detachSession` 约 4275 行）
- Modify: `packages/conatus_code/bin/conatus_code.dart`（`ConatusTuiRuntime.create` 调用约 158 行）
- Modify: `packages/conatus_code/README.md`（Hooks 段后）、`packages/conatus_code/CHANGELOG.md`
- Test: `packages/conatus_code/test/safety/safety_assembly_test.dart`
- Test: `packages/conatus_code/test/tui/tool_safety_reset_test.dart`

**Interfaces:**
- Produces:
  - `class ToolSafety { ToolSafety({required ReadLedger ledger, required RepeatTracker repeat}); void resetSession(); }`
  - `ToolSafety provideToolSafety(Context ctx, {required String workdir, String? home, SafetyConfig config = const SafetyConfig()})`
- Consumes: Task 2 `SafetyConfig`、Task 4/5/6/7 的护栏与中间件。

- [ ] **Step 1: 写失败测试（装配）**

```dart
// test/safety/safety_assembly_test.dart
import 'dart:io';
import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/safety.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('nava-safety-asm'));
  tearDown(() => dir.deleteSync(recursive: true));

  Context build(SafetyConfig config) {
    final Context app = Context.root();
    provideTools(app);
    provideFsTools(
      app,
      options: FsToolOptions(fs: LocalFileSystem(cwd: dir.path), enableSearch: false),
    );
    provideToolSafety(app, workdir: dir.path, config: config);
    addTearDown(app.dispose);
    return app;
  }

  test('默认开启：未读覆盖被拒，读后可写', () async {
    File('${dir.path}${Platform.pathSeparator}a.txt').writeAsStringSync('old');
    final Context app = build(const SafetyConfig());
    final ToolResult denied = await app.tools.call(
      const ToolCall(name: 'write', arguments: <String, Object?>{'path': 'a.txt', 'content': 'new'}),
    );
    expect(denied.isError, isTrue);
    expect(denied.content, startsWith('WRITE_WITHOUT_READ:'));
    await app.tools.call(const ToolCall(name: 'read', arguments: <String, Object?>{'path': 'a.txt'}));
    final ToolResult allowed = await app.tools.call(
      const ToolCall(name: 'write', arguments: <String, Object?>{'path': 'a.txt', 'content': 'new'}),
    );
    expect(allowed.isError, isFalse);
  });

  test('全关：未读覆盖放行', () async {
    File('${dir.path}${Platform.pathSeparator}a.txt').writeAsStringSync('old');
    final Context app = build(const SafetyConfig(
      requireReadBeforeWrite: false,
      repeatWarnAt: 0,
      repeatDenyAt: 0,
      protectPrivateKeys: false,
      denyDotenvWrites: false,
    ));
    final ToolResult r = await app.tools.call(
      const ToolCall(name: 'write', arguments: <String, Object?>{'path': 'a.txt', 'content': 'new'}),
    );
    expect(r.isError, isFalse);
  });

  test('resetSession 清空台账与计数', () {
    final Context app = build(const SafetyConfig());
    final ToolSafety safety = app.require<ToolSafety>('toolSafety');
    safety.ledger.note('/x', 'v');
    expect(safety.ledger.length, 1);
    safety.resetSession();
    expect(safety.ledger.length, 0);
  });
}
```

- [ ] **Step 2: 写失败测试（会话切换复位）**

```dart
// test/tui/tool_safety_reset_test.dart
import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/safety.dart';
import 'package:test/test.dart';
import 'session_rename_fixture.dart';

void main() {
  test('切换会话清空读台账', () async {
    final RenameFixture fix = await buildRenameFixture();
    provideToolSafety(fix.app, workdir: fix.sessionsDir.parent.path);
    final ToolSafety safety = fix.app.require<ToolSafety>('toolSafety');
    safety.ledger.note('/x', 'v');
    expect(await fix.controller.switchSession(renameOtherId), isTrue);
    expect(safety.ledger.length, 0);
  });
}
```

- [ ] **Step 3: 运行测试确认失败**

Run: `cd packages/conatus_code && dart test test/safety/safety_assembly_test.dart test/tui/tool_safety_reset_test.dart -r expanded`
Expected: FAIL — `provideToolSafety` / `ToolSafety` 未定义；控制器未复位。

- [ ] **Step 4: 实现装配入口**

`provideToolSafety`：创建 `ReadLedger` / `RepeatTracker`，`ctx.provide('toolSafety', ...)`；
按配置分别 `ctx.effect(() => ctx.tools.guard(guard.check))` 与
`ctx.effect(() => ctx.tools.use(middleware.call, tag: '...'))`：

- 读后写：`ReadBeforeWriteGuard` + `ReadLedgerMiddleware`，tag `'readLedger'`；
- 重复：`RepeatTracker` + `RepeatWarning`，tag `'repeatBreaker'`；
- 敏感：`SensitivePathGuard`（无中间件）。

`lib/safety.dart` 增加：

```dart
export 'src/safety/safety_assembly.dart' show ToolSafety, provideToolSafety;
```

- [ ] **Step 5: 接线与文档**

`tui_app.dart`：`create` 增加参数 `SafetyConfig safety = const SafetyConfig()`；在
`provideTools(app, ...)` 之后调用
`provideToolSafety(app, workdir: canonicalWorkdir, home: instructionHome ?? defaultInstructionHome(), config: safety);`
（新增 import `../instructions/instruction_paths.dart` 与 `../safety/safety_assembly.dart`）。

`tui_controller.dart`：`_bind` 中 `_session = session;` 之后、`_detachSession` 中
`_session = null;` 之后各加
`_app.get<ToolSafety>('toolSafety')?.resetSession();`（相对导入 `../safety/safety_assembly.dart`）。

`bin/conatus_code.dart`：`ConatusTuiRuntime.create` 调用加 `safety: config.safety,`。

README 在 Hooks 段后新增「## 安全护栏（`[safety]`）」：列出配置表、三项行为、
`.env` 读 ask / 写拒绝的差异、`bash` 字面路径的已知盲区。CHANGELOG「未发布」加
三条 bullet（读后写、重复熔断、敏感文件），并标注 `.env` 写入是行为变更。

- [ ] **Step 6: 运行测试确认通过**

Run: `cd packages/conatus_code && dart test test/safety test/tui/tool_safety_reset_test.dart -r expanded`
Expected: PASS。

- [ ] **Step 7: 提交**

```bash
git add lib/src/safety/safety_assembly.dart lib/safety.dart lib/src/tui/tui_app.dart lib/src/tui/tui_controller.dart bin/conatus_code.dart README.md CHANGELOG.md test/safety/safety_assembly_test.dart test/tui/tool_safety_reset_test.dart
git commit -m "feat(safety): 装配工具层护栏与会话复位"
```

---

### Task 9: 全量验证与交付

**Files:**
- Modify: `packages/conatus_code/CHANGELOG.md`（若 Task 8 未覆盖）
- No source changes expected.

**Interfaces:**
- Consumes: 全部前序任务。
- Produces: 可发布的 `dist/nava` 与通过验证的提交。

- [ ] **Step 1: 静态检查**

Run: `cd packages/conatus_code && dart analyze --fatal-infos`
Expected: `No issues found!`

- [ ] **Step 2: 全量测试**

Run: `cd packages/conatus_code && dart test`
Expected: 全部通过，无新增 skip。

- [ ] **Step 3: 重建二进制**

Run: `cd packages/conatus_code && bash tool/build_binary.sh`
Expected: 产出 `dist/nava`，退出码 0。

- [ ] **Step 4: 手工冒烟（交互式）**

```bash
cd /tmp && mkdir -p nava-safety-smoke && cd nava-safety-smoke
printf 'old\n' > a.txt
nava
# 输入：覆盖 a.txt 但不先读 → 期望 WRITE_WITHOUT_READ；read 后再写 → 成功
# 输入：重复同一 bash 命令 5 次 → 第 5 次 REPEAT_CALL_BLOCKED
# 输入：read ~/.ssh/id_rsa → SENSITIVE_PATH
```

Expected: 三种护栏按上述文案生效；`/doctor` 启动正常。

- [ ] **Step 5: 提交并推送**

```bash
cd packages/conatus_code
git add CHANGELOG.md
git commit -m "docs(changelog): 记录工具层安全护栏"
git push
```

- [ ] **Step 6: 父仓库同步 gitlink**

```bash
cd /Users/fitz/REPO/conatus
git add packages/conatus_code
git commit -m "chore(code): 同步子模块 gitlink（工具层安全护栏）"
git push
```

Expected: 父仓库只出现 gitlink 变更；`bash tool/version.sh` 仍通过。

---

## 计划自检

- **Spec 覆盖**：读后写（Task 1/4/5）、重复熔断（Task 6）、敏感文件（Task 7）、
  配置（Task 2）、装配/复位/文档（Task 8）、验证（Task 9）。spec §12 的后续项
  明确不在本计划内。
- **类型一致性**：`ReadLedger` / `fileFingerprint` / `canonicalToolPath` /
  `patchTargets` / `RepeatTracker` / `SensitivePathGuard` 的签名在各任务
  Interfaces 与实现步骤中一致。
- **Review Focus 对应**：路径拼写（Task 5 符号链接/`./` 用例）、非文本读取
  （Task 4 无 version 用例）、`apply_patch` Add/Update（Task 3/5）、会话生命周期
  （Task 8 两个用例）、敏感文件豁免（Task 7 规则表）。
