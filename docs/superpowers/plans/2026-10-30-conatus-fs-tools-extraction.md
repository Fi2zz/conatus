# conatus_fs_tools 提取实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `conatus_code` 的文件工具与纯 diff 内核提取到父仓，形成 `conatus_diff` 与 `conatus_fs_tools` 两个包，让 nava 与桌面端共用同一套工具实现。

**Architecture:** 纯 diff 算法零依赖进 `conatus_diff`；文件工具进 `conatus_fs_tools`（依赖 core / diff / foundation / glob）；通用只读闸门与 `ToolResultEviction` 类进 `conatus_foundation`；`.opencode` / `.nava` / fs jail / 审批 / TUI 留在 `conatus_code`。nava 用 `lib/fs_tools.dart` re-export 兼容旧入口。

**Tech Stack:** Dart 3.6+、`package:test`、`glob`

**Spec:** `docs/superpowers/specs/2026-10-30-conatus-fs-tools-extraction-design.md`

## Global Constraints

- 全部包：`version: 0.16.0`、`publish_to: none`、`resolution: workspace`、SDK `^3.6.0`（根包 `^3.11.0`）。
- 新增运行时依赖只允许 `glob`（`conatus_fs_tools`）；`conatus_diff` 必须零依赖。
- 新包不得出现 `.nava`、`.opencode`、`nocterm`、`sqlite3`、`toml`、`command_shield`。
- 工具名、参数名、默认值保持不变：`read` / `write` / `edit` / `list` / `glob` / `grep` / `apply_patch`。
- 单文件 ≤200 行、单 class ≤150 行、函数体 ≤40 行、函数参数 ≤4 个；例外加 `// REASON: ...`。
- 布尔命名不用 `is/has/can/should` 前缀；函数名 `动词 + 名词`；面向用户字符串用中文。
- 包内一律相对导入；`prefer_single_quotes`、`always_declare_return_types`、`prefer_final_locals`。
- 父仓与 `conatus_code` 是两个 git 仓库：先父仓提交并推送，再子模块 pin ref、删副本、重建二进制；禁止一个提交跨两仓。
- `products/*` 是产品层 submodule，只依赖伞包 `conatus`，不进伞包 re-export、不进根依赖清单；桌面端通过 `package:conatus/conatus.dart` 使用新包。
- 存在 `products/*` 时，根目录 `dart pub get` 前必须先跑 `bash tool/setup_code_filter.sh`，否则产品的 `resolution: workspace` 仍是注释态、根解析失败。
- 不在本计划中改动 checkpoint 磁盘格式、`/rewind`、`/undo` 行为。

## Review Focus

1. `read` 读取超过 20 MiB 的图片 / PDF：必须返回 `FS_TOO_LARGE`，不能把整文件读进内存后再判断。
2. `write` 的 `create` 命中已存在文件、`edit` 的 `old_string` 多处匹配：必须失败且不改变文件。
3. `grep` 的 pattern 以 `-` 开头或含空格 / 引号：必须放在 `--` 之后作为位置参数，不能被当成 rg flag。
4. `glob` / `list` 遇到符号链接目录：不得跟随、不得越出工作区。
5. `apply_patch` 多文件中途失败：必须返回失败并保留已应用文件（与现状一致），错误不能被吞。
6. `provideFsTools` 所在上下文释放：所有工具注册必须撤销，注册表为空。

每条在对应任务的测试步骤里都有落点。

---

### Task 1: 新建 `conatus_diff` 包并迁出纯 diff 内核

**Files:**
- Create: `packages/conatus_diff/pubspec.yaml`
- Create: `packages/conatus_diff/analysis_options.yaml`
- Create: `packages/conatus_diff/README.md`
- Create: `packages/conatus_diff/lib/conatus_diff.dart`
- Create: `packages/conatus_diff/lib/src/diff_types.dart`
- Create: `packages/conatus_diff/lib/src/diff_model.dart`
- Create: `packages/conatus_diff/lib/src/diff_paths.dart`
- Create: `packages/conatus_diff/lib/src/diff_builder.dart`
- Create: `packages/conatus_diff/lib/src/diff_parser.dart`
- Create: `packages/conatus_diff/lib/src/unified_diff.dart`
- Create: `packages/conatus_diff/lib/src/line_ops.dart`
- Create: `packages/conatus_diff/lib/src/apply.dart`
- Test: `packages/conatus_diff/test/unified_diff_test.dart`
- Test: `packages/conatus_diff/test/diff_parser_test.dart`
- Test: `packages/conatus_diff/test/apply_test.dart`
- Modify: `pubspec.yaml`, `lib/conatus.dart`, `README.md`, `AGENTS.md`, `CHANGELOG.md`

**Interfaces:**
- Consumes: 无。
- Produces（`package:conatus_diff/conatus_diff.dart`）：
  - `enum DiffOpKind { equal, delete, insert }`
  - `class DiffOp { const DiffOp(DiffOpKind kind, String text); }`
  - `class DiffFile { const DiffFile({required String path, required List<DiffHunk> hunks}); }`
  - `class DiffHunk { const DiffHunk({required int oldStart, required int oldLines, required int newStart, required int newLines, required List<String> lines}); }`
  - `enum DiffScope { working, turn }`
  - `class FileDiff extends DiffFile { ... }`
  - `const int kMaxDiffLines = 2000;`
  - `String buildUnifiedDiff({required String oldText, required String newText, required String path, int context = 3, int lcsLimit = kMaxDiffLines})`
  - `List<String> splitLines(String text)`
  - `List<DiffOp> diffLines(List<String> a, List<String> b, {int lcsLimit = kMaxDiffLines})`
  - `List<DiffOp> lineDiffOps(List<String> a, List<String> b, int lcsLimit)`
  - `bool lineDiffCoarse(List<String> a, List<String> b, int lcsLimit)`
  - `List<FileDiff> parseUnifiedDiff(String text)`
  - `class PatchContextException implements Exception { const PatchContextException(String message); }`
  - `String applyDiffFile(String oldText, DiffFile file)`
  - `String? applyEditText(String text, String oldString, String newString, bool replaceAll)`

- [ ] **Step 1: 先复制三个测试，改成新包入口**

从 `packages/conatus_code/test/diff/` 复制 `unified_diff_test.dart`、`diff_parser_test.dart`、`apply_test.dart` 到 `packages/conatus_diff/test/`，把每个文件的入口 import 改为：

```dart
import 'package:conatus_diff/conatus_diff.dart';
```

- [ ] **Step 2: 建包壳并确认测试失败**

写 `packages/conatus_diff/pubspec.yaml`：

```yaml
name: conatus_diff
description: >-
  conatus 的文本差异内核：统一 diff 生成 / 解析、行级 LCS、hunk 应用。
version: 0.16.0
repository: https://github.com/Fi2zz/conatus
issue_tracker: https://github.com/Fi2zz/conatus/issues
publish_to: none

environment:
  sdk: ^3.6.0

resolution: workspace

dependencies: {}

dev_dependencies:
  lints: ^4.0.0
  test: ^1.25.0

topics:
  - diff
  - text
  - patch
```

写 `analysis_options.yaml` 为 `include: ../../analysis_options.yaml`。在仓库根运行：

```bash
git submodule update --init
bash tool/setup_code_filter.sh
dart pub get
cd packages/conatus_diff && dart test
```

预期：编译失败，提示找不到 `lib/conatus_diff.dart`。

- [ ] **Step 3: 复制实现文件**

从 `packages/conatus_code/lib/src/diff/` 复制以下 8 个文件到 `packages/conatus_diff/lib/src/`，文件名不变：

`diff_types.dart`、`diff_model.dart`、`diff_paths.dart`、`diff_builder.dart`、`diff_parser.dart`、`unified_diff.dart`、`line_ops.dart`、`apply.dart`。

这些文件原本就在同一目录，内部相对 import 不需要改；`DiffScope` 保留在 `diff_model.dart`，文档改成“diff 的比较范围”。

- [ ] **Step 4: 写包入口**

`packages/conatus_diff/lib/conatus_diff.dart`：

```dart
/// conatus 的文本差异内核：统一 diff 生成 / 解析、行级 LCS 与 hunk 应用。
///
/// **实验性**：API 可能在没有 major 版本变更的情况下调整。
library;

export 'src/apply.dart'
    show PatchContextException, applyDiffFile, applyEditText;
export 'src/diff_model.dart' show DiffScope, FileDiff;
export 'src/diff_parser.dart' show diffLines, parseUnifiedDiff;
export 'src/diff_types.dart' show DiffFile, DiffHunk, DiffOp, DiffOpKind;
export 'src/line_ops.dart' show lineDiffCoarse, lineDiffOps;
export 'src/unified_diff.dart'
    show buildUnifiedDiff, kMaxDiffLines, splitLines;
```

- [ ] **Step 5: 跑 `conatus_diff` 测试**

Run: `cd packages/conatus_diff && dart test`
Expected: PASS（三个测试文件全绿）。

- [ ] **Step 6: 注册到根包**

在根 `pubspec.yaml` 的 `dependencies` 中，按字母序在 `conatus_cron` 与 `conatus_doc` 之间加入：

```yaml
  conatus_diff: {path: packages/conatus_diff}
```

在 `lib/conatus.dart` 中加入：

```dart
export 'package:conatus_diff/conatus_diff.dart';
```

并把 `lib/conatus.dart` 文件头注释与根 `pubspec.yaml` 顶部注释的数量从 `27 个模块包 / 27 个子包（15 稳定 + 12 实验性）` 改为 `28 / 15 + 13`（本任务只加 `conatus_diff`；Task 4 再加 `conatus_fs_tools` 后变成 29 / 15 + 14）。

- [ ] **Step 7: 更新 README / AGENTS / CHANGELOG**

- 根 `README.md`：在实验性包表格加入 `conatus_diff` 行（说明：文本差异内核；依赖：—）。
- `AGENTS.md`：在实验性包列表加入 `conatus_diff`；把 `packages/` 的 `28 个目录：15 稳定 + 12 实验性 + 1 子模块` 改为 `29 个目录：15 稳定 + 13 实验性 + 1 子模块`（`products/` 计数不变）。
- 根 `CHANGELOG.md` 的 `## [未发布]` 下加入一行：`新增实验性包 conatus_diff：统一 diff 生成/解析/应用，零依赖。`
- 新建 `packages/conatus_diff/README.md`，写用途、API 清单、零依赖说明。
- 用 `rg "27 个|12 个实验性|12 实验性" README.md AGENTS.md lib/conatus.dart pubspec.yaml` 找出所有旧计数，统一改成 28 / 13（本任务只加一个包）。

- [ ] **Step 8: 全仓校验**

Run:
```bash
dart format packages/conatus_diff
dart analyze --fatal-infos
cd packages/conatus_diff && dart test
```
Expected: analyze 无输出；测试通过。

- [ ] **Step 9: 提交**

```bash
git add packages/conatus_diff pubspec.yaml lib/conatus.dart README.md AGENTS.md CHANGELOG.md
git commit -m "feat(diff): 新增 conatus_diff 纯 diff 内核"
```

---

### Task 2: 把 `ToolResultEviction` 类迁到 `conatus_foundation`

**Files:**
- Create: `packages/conatus_foundation/lib/src/tool_result_eviction.dart`
- Modify: `packages/conatus_foundation/lib/conatus_foundation.dart`
- Modify: `packages/conatus_agent/lib/src/tool_result_eviction.dart`
- Modify: `packages/conatus_agent/lib/conatus_agent.dart`
- Test: `packages/conatus_foundation/test/tool_result_eviction_test.dart`（新建）
- Test: `packages/conatus_agent/test/tool_result_eviction_test.dart`（保留，只验证 provider）

**Interfaces:**
- Consumes: `FileSystem`、`FsTarget`、`ToolResult`（foundation）。
- Produces（foundation 入口）：
  - `const int kDefaultToolResultThreshold = 80000;`
  - `const int kDefaultToolResultPreview = 2000;`
  - `class ToolResultEviction { ToolResultEviction({required FileSystem fs, int threshold = kDefaultToolResultThreshold, int previewChars = kDefaultToolResultPreview, String? dir}); Future<String?> evict(String content); Future<void> clear(); List<String> get spilledPaths; }`
- `conatus_agent` 继续导出同名符号（re-export foundation），`provideToolResultEviction` 留在 agent。

- [ ] **Step 1: 写 foundation 侧测试**

`packages/conatus_foundation/test/tool_result_eviction_test.dart`：

```dart
import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  test('超阈值落盘、预览含路径，clear 删除文件', () async {
    final Directory dir = Directory.systemTemp.createTempSync('conatus-evict-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final ToolResultEviction eviction = ToolResultEviction(
      fs: LocalFileSystem(cwd: dir.path),
      threshold: 10,
      previewChars: 2,
      dir: '${dir.path}/spill',
    );
    const String body = 'abcdefghijklmnop';
    final String? preview = await eviction.evict(body);

    expect(preview, isNotNull);
    expect(preview, contains('省略'));
    expect(File(eviction.spilledPaths.single).readAsStringSync(), body);

    await eviction.clear();
    expect(eviction.spilledPaths, isEmpty);
  });
}
```

Run: `cd packages/conatus_foundation && dart test test/tool_result_eviction_test.dart`
Expected: 编译失败，`ToolResultEviction` 未定义。

- [ ] **Step 2: 迁移类与常量**

把 `packages/conatus_agent/lib/src/tool_result_eviction.dart` 中的 `kDefaultToolResultThreshold`、`kDefaultToolResultPreview`、`ToolResultEviction` 类整体复制到 `packages/conatus_foundation/lib/src/tool_result_eviction.dart`。文件顶部 import 改为：

```dart
import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'tool.dart';
import 'tool_types.dart';
```

在 `packages/conatus_foundation/lib/conatus_foundation.dart` 中加入：

```dart
export 'src/tool_result_eviction.dart'
    show
        ToolResultEviction,
        kDefaultToolResultPreview,
        kDefaultToolResultThreshold;
```

- [ ] **Step 3: 让 agent 不再声明类，只保留 provider**

`packages/conatus_agent/lib/src/tool_result_eviction.dart` 删除类与常量，文件只保留 `provideToolResultEviction(...)`，并在顶部加入：

```dart
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
```

把 `conatus_agent/lib/conatus_agent.dart` 中原有的：

```dart
export 'src/tool_result_eviction.dart'
    show ToolResultEviction, kDefaultToolResultPreview,
        kDefaultToolResultThreshold, provideToolResultEviction;
```

改为：

```dart
export 'package:conatus_foundation/conatus_foundation.dart'
    show
        ToolResultEviction,
        kDefaultToolResultPreview,
        kDefaultToolResultThreshold;
export 'src/tool_result_eviction.dart' show provideToolResultEviction;
```

- [ ] **Step 4: 跑 foundation 与 agent 测试**

Run:
```bash
cd packages/conatus_foundation && dart test test/tool_result_eviction_test.dart
cd ../conatus_agent && dart test test/tool_result_eviction_test.dart
```
Expected: 两个都 PASS。

- [ ] **Step 5: 全仓 analyze**

Run: `dart analyze --fatal-infos`
Expected: 无输出。若出现 `ToolResultEviction` 二义性，说明 agent 仍在本地声明类，回到 Step 3 删除。

- [ ] **Step 6: 提交**

```bash
git add packages/conatus_foundation packages/conatus_agent
git commit -m "refactor(foundation): ToolResultEviction 类迁入 foundation"
```

---

### Task 3: 把只读闸门与通用路径助手迁到 `conatus_foundation`

**Files:**
- Create: `packages/conatus_foundation/lib/src/fs_read_only_paths.dart`
- Create: `packages/conatus_foundation/lib/src/fs_read_only_guard.dart`
- Modify: `packages/conatus_foundation/lib/conatus_foundation.dart`
- Create: `packages/conatus_code/lib/src/read_only_policy.dart`
- Delete: `packages/conatus_code/lib/src/read_only_paths.dart`
- Delete: `packages/conatus_code/lib/src/fs_tools/read_only_path_guard.dart`
- Modify: `packages/conatus_code/lib/fs_tools.dart`
- Modify: `packages/conatus_code/lib/src/tools/protected_command.dart`
- Modify: `packages/conatus_code/lib/src/checkpoint/checkpoint_paths.dart`
- Modify: `packages/conatus_code/lib/src/config/config_atomic_write.dart`
- Modify: `packages/conatus_code/lib/src/config/config_path.dart`
- Modify: `packages/conatus_code/lib/src/config/project_data_dir.dart`
- Modify: `packages/conatus_code/lib/src/mcp/mcp_cli.dart`
- Modify: `packages/conatus_code/lib/src/project/project_registry.dart`
- Modify: `packages/conatus_code/lib/src/story/story_pending.dart`
- Test: `packages/conatus_foundation/test/fs_read_only_guard_test.dart`（新建）
- Test: `packages/conatus_code/test/fs_tools/read_only_policy_test.dart`（新建）
- Delete: `packages/conatus_code/test/fs_tools/read_only_path_guard_test.dart`

**Interfaces:**
- Produces（foundation）：
  - `class ReadOnlyPathGuard implements FileSystem { ReadOnlyPathGuard({required FileSystem inner, required List<String> protectedRoots, String deniedMessage = 'READ_ONLY_PATH: 目标目录只读'}); }`
  - `String normalizeReadOnlyPath(String path)`
  - `bool underReadOnlyRoot(String path, String root)`
  - `String? realPathViaAncestor(String path)`
- `conatus_code/lib/src/read_only_policy.dart` 保留：
  - `kReadOnlyPathCode`、`kReadOnlyPathMessage`、`kOpenCodeDirName`、`kGlobalOpenCodePath`
  - `defaultReadOnlyRoots(String workdir, {String? home})`
  - `readOnlyRelativePath(String path)`
  - `readOnlyWritePath(String path, {String? workdir, String? home})`

- [ ] **Step 1: 写 foundation 闸门测试**

把 `packages/conatus_code/test/fs_tools/read_only_path_guard_test.dart` 复制为 `packages/conatus_foundation/test/fs_read_only_guard_test.dart`，做三处改动：

1. import 改为 `package:conatus_foundation/conatus_foundation.dart`。
2. `protectedRoots: defaultReadOnlyRoots(dir.path)` 改为 `protectedRoots: <String>['${dir.path}/.opencode']`。
3. 删除 `defaultReadOnlyRoots ...`、`全局 ~/.config/opencode ...`、`大小写变体 ...` 三个用例（它们属于产品策略，Step 5 放到 nava 测试）；保留 write/edit/remove/ancestor/reads/outside/symlink/alias/jail 用例。

再加一个用例：

```dart
test('deniedMessage 可注入', () async {
  final ReadOnlyPathGuard custom = ReadOnlyPathGuard(
    inner: LocalFileSystem(),
    protectedRoots: <String>['${dir.path}/.opencode'],
    deniedMessage: 'APP_CONFIG_READ_ONLY',
  );
  final FsTarget target =
      await custom.resolve('${dir.path}/.opencode/x');
  expect(
    () => custom.writeText(target, 'x'),
    throwsA(isA<FsError>().having(
      (FsError e) => e.message,
      'message',
      contains('APP_CONFIG_READ_ONLY'),
    )),
  );
});
```

Run: `cd packages/conatus_foundation && dart test test/fs_read_only_guard_test.dart`
Expected: 编译失败，`ReadOnlyPathGuard` 未定义。

- [ ] **Step 2: 迁移通用实现**

- 把 `conatus_code/lib/src/read_only_paths.dart` 中的 `normalizeReadOnlyPath`、`underReadOnlyRoot`、`realPathViaAncestor`、`_comparable`、`_join` 复制到 `packages/conatus_foundation/lib/src/fs_read_only_paths.dart`。
- 把 `conatus_code/lib/src/fs_tools/read_only_path_guard.dart` 整体复制到 `packages/conatus_foundation/lib/src/fs_read_only_guard.dart`，把 import 改为：

```dart
import 'dart:io';
import 'dart:typed_data';

import 'fs.dart';
import 'fs_read_only_paths.dart';
import 'fs_types.dart';
```

- 构造函数加 `this.deniedMessage = 'READ_ONLY_PATH: 目标目录只读'`，`_throwDenied` 改为 `throw FsError(FsErrorCode.permissionDenied, deniedMessage);`。
- foundation 入口加入：

```dart
export 'src/fs_read_only_guard.dart' show ReadOnlyPathGuard;
export 'src/fs_read_only_paths.dart'
    show normalizeReadOnlyPath, realPathViaAncestor, underReadOnlyRoot;
```

Run: `cd packages/conatus_foundation && dart test test/fs_read_only_guard_test.dart`
Expected: PASS。

- [ ] **Step 3: 在 nava 建产品策略文件**

新建 `packages/conatus_code/lib/src/read_only_policy.dart`，内容为原 `read_only_paths.dart` 中保留下来的产品部分，并 import foundation：

```dart
import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';

const String kReadOnlyPathCode = 'READ_ONLY_PATH';
const String kReadOnlyPathMessage =
    'READ_ONLY_PATH: .opencode 目录只读（含 ~/.config/opencode）';
const String kOpenCodeDirName = '.opencode';
const String kGlobalOpenCodePath = '~/.config/opencode';

List<String> defaultReadOnlyRoots(String workdir, {String? home}) {
  final String sep = Platform.pathSeparator;
  final String? resolvedHome =
      home ?? Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  return <String>[
    normalizeReadOnlyPath('${Directory(workdir).absolute.path}$sep.opencode'),
    if (resolvedHome != null && resolvedHome.isNotEmpty)
      normalizeReadOnlyPath('$resolvedHome$sep.config${sep}opencode'),
  ];
}

bool readOnlyRelativePath(String path) { /* 原实现 */ }

bool readOnlyWritePath(String path, {String? workdir, String? home}) {
  /* 原实现，改用 foundation 的 underReadOnlyRoot / realPathViaAncestor */
}
```

删除 `packages/conatus_code/lib/src/read_only_paths.dart`。

- [ ] **Step 4: 更新 nava import 与入口**

把以下文件的 `../read_only_paths.dart` / `../../read_only_paths.dart` 全部改为 `../read_only_policy.dart`：

`src/tools/protected_command.dart`、`src/checkpoint/checkpoint_paths.dart`、
`src/config/config_atomic_write.dart`、`src/config/config_path.dart`、
`src/config/project_data_dir.dart`、`src/mcp/mcp_cli.dart`、
`src/project/project_registry.dart`、`src/story/story_pending.dart`。

`packages/conatus_code/lib/fs_tools.dart` 改为：

```dart
export 'package:conatus_foundation/conatus_foundation.dart'
    show ReadOnlyPathGuard, normalizeReadOnlyPath;
export 'src/read_only_policy.dart'
    show
        defaultReadOnlyRoots,
        kGlobalOpenCodePath,
        kOpenCodeDirName,
        kReadOnlyPathCode,
        kReadOnlyPathMessage,
        readOnlyRelativePath,
        readOnlyWritePath;
```

`src/tui/tui_app.dart` 的 `ReadOnlyPathGuard` 继续通过 `package:conatus_foundation` 使用；构造时加 `deniedMessage: kReadOnlyPathMessage`。

删除 `packages/conatus_code/lib/src/fs_tools/read_only_path_guard.dart`（实现已迁到 foundation）。

- [ ] **Step 5: 产品策略测试放到 nava**

新建 `packages/conatus_code/test/fs_tools/read_only_policy_test.dart`，只保留原 guard 测试里三个产品用例：

```dart
test('defaultReadOnlyRoots covers project and global opencode dirs', ...);
test('全局 ~/.config/opencode 由 home 注入同样只读', ...);
test('大小写变体 .OPENCODE 也算受保护（APFS 大小写不敏感）', ...);
```

删除 `packages/conatus_code/test/fs_tools/read_only_path_guard_test.dart`。

- [ ] **Step 6: 跑两仓相关测试**

Run:
```bash
cd packages/conatus_foundation && dart test test/fs_read_only_guard_test.dart
cd ../../packages/conatus_code && dart test test/fs_tools/read_only_policy_test.dart
dart analyze --fatal-infos
```
Expected: 全绿；analyze 无输出。

- [ ] **Step 7: 提交**

父仓与子模块分别提交：

```bash
# 父仓
git add packages/conatus_foundation
git commit -m "refactor(foundation): 通用只读路径闸门迁入 foundation"

# 子模块
cd packages/conatus_code
git add lib/src/read_only_policy.dart lib/fs_tools.dart lib/src test/fs_tools
git commit -m "refactor(code): .opencode 只读策略改为使用 foundation 闸门"
```

---

### Task 4: 新建 `conatus_fs_tools` 核心工具包

**Files:**
- Create: `packages/conatus_fs_tools/pubspec.yaml`
- Create: `packages/conatus_fs_tools/analysis_options.yaml`
- Create: `packages/conatus_fs_tools/README.md`
- Create: `packages/conatus_fs_tools/lib/conatus_fs_tools.dart`
- Create: `packages/conatus_fs_tools/lib/src/fs_tools.dart`
- Create: `packages/conatus_fs_tools/lib/src/read_file.dart`
- Create: `packages/conatus_fs_tools/lib/src/read_file_text.dart`
- Create: `packages/conatus_fs_tools/lib/src/read_file_attachments.dart`
- Create: `packages/conatus_fs_tools/lib/src/read_file_directory.dart`
- Create: `packages/conatus_fs_tools/lib/src/write_file.dart`
- Create: `packages/conatus_fs_tools/lib/src/edit_file.dart`
- Create: `packages/conatus_fs_tools/lib/src/glob_tool.dart`
- Create: `packages/conatus_fs_tools/lib/src/list_files.dart`
- Test: `packages/conatus_fs_tools/test/{read_file,write_file,edit_file,glob_tool,fs_tools}_test.dart`
- Test: `packages/conatus_fs_tools/test/list_files_test.dart`
- Test: `packages/conatus_fs_tools/test/standalone_consumer_test.dart`
- Test: `packages/conatus_fs_tools/test/support/fake_shell.dart`
- Modify: `pubspec.yaml`, `lib/conatus.dart`, `README.md`, `AGENTS.md`, `CHANGELOG.md`

**Interfaces:**
- Consumes: `conatus_core`、`conatus_diff`、`conatus_foundation`、`glob`。
- Produces：
  - `const Set<String> kDefaultSkipDirs = <String>{'.git', 'node_modules', '.dart_tool', 'build'};`
  - `class FsToolOptions { const FsToolOptions({FileSystem? fs, ToolRegistry? tools, ShellExecutor? shell, ToolResultEviction? eviction, RipgrepBinary? ripgrep, int defaultReadLimit = 2000, int maxReadChars = 200000, int rgLimit = 50, bool enableSearch = true, bool enableList = true, Set<String> skipDirs = kDefaultSkipDirs}); }`
  - `List<Tool> provideFsTools(Context ctx, {FsToolOptions options = const FsToolOptions()})`
  - `class GlobTool extends Tool { const GlobTool({required FileSystem fs, int defaultLimit = 100, Set<String> skipDirs = kDefaultSkipDirs}); }`
  - `class ListLimits { const ListLimits({int defaultDepth = 1, int maxDepth = 5, int defaultLimit = 200}); }`
  - `class ListFilesTool extends Tool { const ListFilesTool({required FileSystem fs, ListLimits limits = const ListLimits(), Set<String> skipDirs = kDefaultSkipDirs}); }`
  - `class ReadFileTool`、`WriteFileTool`、`EditFileTool` 保持原工具名与参数。
- 任务 4 默认注册：`read`、`write`、`edit`、`list`、`glob`。`grep` 由 Task 6 接入 `RipgrepRunner` 后注册；本任务不复制 `ripgrep_*` 文件。

- [ ] **Step 1: 先复制测试并改入口**

复制以下测试到 `packages/conatus_fs_tools/test/`：

- `test/fs_tools/read_file_test.dart`
- `test/fs_tools/write_file_test.dart`
- `test/fs_tools/edit_file_test.dart`
- `test/fs_tools/glob_tool_test.dart`
- `test/fs_tools/fs_tools_test.dart`
- `test/tools/list_files_test.dart`
- `test/fs_tools/support/fake_shell.dart`

把所有 `package:conatus_code/fs_tools.dart` 改为 `package:conatus_fs_tools/conatus_fs_tools.dart`；`list_files_test.dart` 的 `package:conatus_code/conatus_code.dart` 也改为新入口。

把 `fs_tools_test.dart` 的三处期望改成新默认集：

```dart
expect(registered.map((Tool t) => t.name),
    containsAll(<String>['read', 'write', 'edit', 'list', 'glob']));
expect(registered.map((Tool t) => t.name), isNot(contains('grep')));
expect(registered.map((Tool t) => t.name), isNot(contains('apply_patch')));
```

`enableSearch=false` 的用例期望改为 `['read', 'write', 'edit', 'list']`。**删除**原文件里“有 shell 且注入 ripgrep → 注册 rg”的用例——`grep` 在 Task 6 才接入，Task 6 会补回这条用例。

同一文件里旧的命名参数调用也要改成 options：

```dart
// 旧
provideFsTools(ctx, shell: shell, ripgrep: binary);
provideFsTools(ctx, enableSearch: false);
// 新
provideFsTools(ctx, options: FsToolOptions(shell: shell, ripgrep: binary));
provideFsTools(ctx, options: const FsToolOptions(enableSearch: false));
```

补两个 Review Focus 用例：

`read_file_test.dart` 加“超过 20 MiB 的图片直接失败”：

```dart
test('图片超过 20 MiB → FS_TOO_LARGE', () async {
  final File big = File('${dir.path}/big.png');
  big.writeAsBytesSync(List<int>.filled(20 * 1024 * 1024 + 1, 0));

  final ToolResult result =
      await tool.call(_context(<String, Object?>{'path': big.path}));

  expect(result.isError, isTrue);
  expect(result.error?.code, 'FS_TOO_LARGE');
});
```

`glob_tool_test.dart` 加“符号链接目录不跟随”：

```dart
test('符号链接目录不跟随', () async {
  final Directory outside = Directory.systemTemp.createTempSync('conatus-out-');
  addTearDown(() {
    if (outside.existsSync()) outside.deleteSync(recursive: true);
  });
  File('${outside.path}/secret.dart').writeAsStringSync('');
  Link('${dir.path}/link').createSync(outside.path);

  final ToolResult result = await tool
      .call(_context(<String, Object?>{'pattern': '**/*.dart'}));

  final List<Object?> matches =
      (result.value! as Map<String, Object?>)['matches']! as List<Object?>;
  expect(matches, isNot(contains('${outside.path}/secret.dart')));
});
```

- [ ] **Step 2: 建包壳并确认失败**

`packages/conatus_fs_tools/pubspec.yaml`：

```yaml
name: conatus_fs_tools
description: >-
  conatus 的文件工具：read / write / edit / list / glob / grep / apply_patch
  与 provideFsTools 装配。
version: 0.16.0
repository: https://github.com/Fi2zz/conatus
issue_tracker: https://github.com/Fi2zz/conatus/issues
publish_to: none

environment:
  sdk: ^3.6.0

resolution: workspace

dependencies:
  conatus_core: {path: ../conatus_core}
  conatus_diff: {path: ../conatus_diff}
  conatus_foundation: {path: ../conatus_foundation}
  glob: ^2.2.0

dev_dependencies:
  lints: ^4.0.0
  test: ^1.25.0

topics:
  - tools
  - filesystem
  - agent
```

`analysis_options.yaml` 为 `include: ../../analysis_options.yaml`。根目录 `dart pub get`，然后 `cd packages/conatus_fs_tools && dart test`，预期编译失败。

- [ ] **Step 3: 复制并拆分读取工具**

复制 `read_file.dart` 后拆成四个文件，行为不变：

- `read_file.dart`：`ReadFileTool`，只负责参数、`stat` 分派、错误映射。
- `read_file_text.dart`：`ReadFileText`，负责分页、行号格式化、2000 字符行截断、`maxChars` 截断。
- `read_file_attachments.dart`：`ReadFileAttachments`，负责图片 / PDF、20 MiB 限制、`ToolImage` / `ToolFile`。**先 `stat` 看 `size`，超过 20 MiB 直接返回 `FS_TOO_LARGE`，再 `readBytes`**，避免把整文件读进内存后才拒绝。
- `read_file_directory.dart`：`ReadFileDirectory`，负责非递归目录列举。

`ReadFileTool.call` 的骨架：

```dart
final FsTarget target = await _fs.resolve(path);
final FsInfo? info = await _fs.stat(target);
if (info == null) return _error('FS_NOT_FOUND', '文件不存在："$path"');
if (info.type == FsFileType.directory) {
  return ReadFileDirectory(_fs).read(target, path);
}
if (info.type != FsFileType.file) {
  return _error('FS_NOT_REGULAR_FILE', '不是普通文件："$path"');
}
final String? imageMime = ReadFileAttachments.imageMime(path);
if (imageMime != null) {
  return ReadFileAttachments(_fs).readImage(target, imageMime, path);
}
if (path.toLowerCase().endsWith('.pdf')) {
  return ReadFileAttachments(_fs).readPdf(target, path);
}
return ReadFileText(
  _fs,
  defaultLimit: defaultLimit,
  maxChars: maxChars,
).read(
  target,
  path,
  offset: ctx.optional<int>('offset') ?? 1,
  limit: ctx.optional<int>('limit'),
  withLineNumbers: ctx.optional<bool>('with_line_numbers') ?? true,
  version: info.version,
);
```

每个 helper 类保持 <150 行；`ReadFileTool` 保持 <150 行。

- [ ] **Step 4: 迁移其余工具并参数化跳过目录**

- `write_file.dart` / `edit_file.dart`：把 `import '../diff/unified_diff.dart'` 改为 `import 'package:conatus_diff/conatus_diff.dart';`。
- `glob_tool.dart`：删除静态 `_skipDirs`，构造参数加 `this.skipDirs = kDefaultSkipDirs`，`_walk` 用 `skipDirs.contains(entry.name)`。
- `list_files.dart`：从 `src/tools/` 复制；删除静态 `_skipDirs`，构造参数改为 `this.limits = const ListLimits(), this.skipDirs = kDefaultSkipDirs`；原 `defaultDepth/maxDepth/defaultLimit` 改读 `limits`；工具描述不要写死 `.nava`，改成“跳过依赖 / 构建目录”。
- `fs_tools.dart`：实现 `kDefaultSkipDirs`、`FsToolOptions`、`provideFsTools`。

`provideFsTools` 注册规则：

```dart
final FileSystem resolvedFs = options.fs ?? ctx.require<FileSystem>('fs');
final ToolRegistry registry = options.tools ?? ctx.tools;
final List<Tool> registered = <Tool>[
  ReadFileTool(
    fs: resolvedFs,
    defaultLimit: options.defaultReadLimit,
    maxChars: options.maxReadChars,
  ),
  WriteFileTool(fs: resolvedFs),
  EditFileTool(fs: resolvedFs),
  if (options.enableList)
    ListFilesTool(fs: resolvedFs, skipDirs: options.skipDirs),
];
if (options.enableSearch) {
  registered.add(GlobTool(fs: resolvedFs, skipDirs: options.skipDirs));
}
for (final Tool tool in registered) {
  ctx.effect(() => registry.register(tool));
}
return registered;
```

- [ ] **Step 5: 写包入口与独立消费者测试**

`lib/conatus_fs_tools.dart` 导出 `EditFileTool`、`GlobTool`、`ListFilesTool`、`ListLimits`、`ReadFileTool`、`WriteFileTool`、`WriteMode`、`FsToolOptions`、`provideFsTools`、`kDefaultSkipDirs`。

`test/standalone_consumer_test.dart`：

```dart
import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_fs_tools/conatus_fs_tools.dart';
import 'package:test/test.dart';

void main() {
  test('不依赖 conatus_agent 也能装配文件工具，释放后撤销注册', () {
    final Directory dir = Directory.systemTemp.createTempSync('conatus-fs-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final Context ctx = Context.root();
    provideFileSystemLocal(ctx, fs: LocalFileSystem(cwd: dir.path));
    final ToolRegistry tools = provideTools(ctx);

    final List<Tool> registered = provideFsTools(ctx);

    expect(registered.map((Tool t) => t.name),
        containsAll(<String>['read', 'write', 'edit', 'list', 'glob']));
    ctx.dispose();
    expect(tools.names, isEmpty);
  });
}
```

- [ ] **Step 6: 跑测试**

Run:
```bash
cd packages/conatus_fs_tools
dart test
dart test test/standalone_consumer_test.dart
```
Expected: 全绿；`standalone_consumer_test` 不 import `conatus_agent` 也能编译。

- [ ] **Step 7: 注册到根包与文档**

- 根 `pubspec.yaml` 在 `conatus_foundation` 后按字母序加入 `conatus_fs_tools: {path: packages/conatus_fs_tools}`。
- `lib/conatus.dart` 加入 `export 'package:conatus_fs_tools/conatus_fs_tools.dart';`。
- 根 `README.md` 实验性表格加 `conatus_fs_tools` 行；依赖列写 `conatus_core`、`conatus_diff`、`conatus_foundation`、`glob`。
- 根 `README.md` 底部“文本 TUI、文件系统工具与编码工具已并入 conatus_code”的说明改为：TUI / coding 留在 `conatus_code`，文件工具回到 `conatus_fs_tools`。
- `AGENTS.md` 实验性列表加 `conatus_fs_tools`；`packages/` 目录数改为 `30 个目录：15 稳定 + 14 实验性 + 1 子模块`（`products/` 计数不变）。
- 根 `pubspec.yaml` 顶部注释与 `lib/conatus.dart` 文件头从 28 / 15+13 改为 29 / 15+14。
- 用 `rg "28 个|13 个实验性|13 实验性" README.md AGENTS.md lib/conatus.dart pubspec.yaml` 找出所有旧计数，统一改成 29 / 14。
- 新建包 README：说明工具表、`FsToolOptions`、宿主必须自己提供 `ReadOnlyPathGuard` / 溢出目录 / 审批，不包含 `.nava` / `.opencode` 策略。
- 包 README 的桌面端接入示例必须走伞包（`products/*` 的约束），不直接依赖 `conatus_fs_tools`：

```yaml
# products/conatus_work/pubspec.yaml（独立形态）
dependencies:
  conatus:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: <conatus-sha>}
```

```dart
import 'package:conatus/conatus.dart';

void main() {
  final Context ctx = Context.root();
  provideFileSystemLocal(
    ctx,
    fs: ReadOnlyPathGuard(
      inner: LocalFileSystem(cwd: Directory.current.path),
      protectedRoots: <String>[/* 产品自己的配置目录 */],
    ),
  );
  provideTools(ctx);
  provideFsTools(
    ctx,
    options: const FsToolOptions(enablePatch: true),
  );
}
```

- [ ] **Step 8: 全仓校验并提交**

Run:
```bash
dart format packages/conatus_fs_tools
dart analyze --fatal-infos
cd packages/conatus_fs_tools && dart test
```
Expected: 全绿。

```bash
git add packages/conatus_fs_tools pubspec.yaml lib/conatus.dart README.md AGENTS.md CHANGELOG.md
git commit -m "feat(fs_tools): 新增 conatus_fs_tools 文件工具包"
```

---

### Task 5: 迁入 `apply_patch` 与审批差异预览

**Files:**
- Create: `packages/conatus_fs_tools/lib/src/apply_patch.dart`
- Create: `packages/conatus_fs_tools/lib/src/opencode_patch.dart`
- Create: `packages/conatus_fs_tools/lib/src/opencode_patch_apply.dart`
- Create: `packages/conatus_fs_tools/lib/src/preview.dart`
- Modify: `packages/conatus_fs_tools/lib/src/fs_tools.dart`
- Modify: `packages/conatus_fs_tools/lib/conatus_fs_tools.dart`
- Test: `packages/conatus_fs_tools/test/apply_patch_test.dart`
- Test: `packages/conatus_fs_tools/test/preview_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `parseUnifiedDiff`、`applyDiffFile`、`applyEditText`、`DiffFile`、`DiffHunk`。
- Produces：
  - `class ApplyPatchTool extends Tool`
  - `Future<String?> buildApprovalPreview(FileSystem? fs, String toolName, Map<String, Object?> args)`
  - `const int kPreviewMaxChars = 8000;`
  - `FsToolOptions` 新增 `bool enablePatch = false`。

- [ ] **Step 1: 复制测试并改入口**

复制 `test/tools/apply_patch_test.dart`、`test/diff/preview_test.dart` 到新包，import 改为 `package:conatus_fs_tools/conatus_fs_tools.dart`。

在 `apply_patch_test.dart` 末尾加：

```dart
test('多文件 patch 第二个失败：返回失败，已应用文件保持已应用', () async {
  File('${dir.path}/a.txt').writeAsStringSync('a\n');
  File('${dir.path}/b.txt').writeAsStringSync('b\n');
  const String patch = '''
--- a/a.txt
+++ b/a.txt
@@ -1 +1 @@
-a
+A
--- a/b.txt
+++ b/b.txt
@@ -1 +1 @@
-nope
+B
''';

  final ToolResult result = await tool.call(
    _context(<String, Object?>{'patch': patch}),
  );

  expect(result.isError, isTrue);
  expect(File('${dir.path}/a.txt').readAsStringSync(), 'A\n');
  expect(File('${dir.path}/b.txt').readAsStringSync(), 'b\n');
});
```

Run: `cd packages/conatus_fs_tools && dart test test/apply_patch_test.dart`，预期失败。

- [ ] **Step 2: 复制实现并改 import**

复制 `apply_patch.dart`、`opencode_patch.dart`、`opencode_patch_apply.dart`、`preview.dart` 到新包 `lib/src/`。把 `apply_patch.dart` 与 `preview.dart` 中的 `../diff/...` import 改为：

```dart
import 'package:conatus_diff/conatus_diff.dart';
```

- [ ] **Step 3: 接入 `FsToolOptions.enablePatch`**

在 `FsToolOptions` 增加 `this.enablePatch = false` 字段；`provideFsTools` 在 `enableList` 之后加：

```dart
if (options.enablePatch) {
  registered.add(ApplyPatchTool(fs: resolvedFs));
}
```

包入口导出 `ApplyPatchTool`、`buildApprovalPreview`、`kPreviewMaxChars`；包 README 的工具表加上 `apply_patch` 与 `enablePatch` 说明（默认关闭，高风险工具由宿主开启）。

- [ ] **Step 4: 跑测试**

Run:
```bash
cd packages/conatus_fs_tools
dart test test/apply_patch_test.dart test/preview_test.dart
dart test
```
Expected: 全绿。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_fs_tools
git commit -m "feat(fs_tools): 迁入 apply_patch 与审批差异预览"
```

---

### Task 6: 加 `RipgrepRunner` 接缝，修 Windows / 桌面端命令执行

**Files:**
- Create: `packages/conatus_fs_tools/lib/src/ripgrep_runner.dart`
- Create: `packages/conatus_fs_tools/lib/src/ripgrep_binary.dart`
- Create: `packages/conatus_fs_tools/lib/src/ripgrep_tool.dart`
- Modify: `packages/conatus_fs_tools/lib/src/fs_tools.dart`
- Modify: `packages/conatus_fs_tools/lib/conatus_fs_tools.dart`
- Test: `packages/conatus_fs_tools/test/ripgrep_tool_test.dart`
- Test: `packages/conatus_fs_tools/test/ripgrep_runner_test.dart`
- Test: `packages/conatus_fs_tools/test/ripgrep_binary_test.dart`

**Interfaces:**
- Produces：
  - `class RipgrepRunResult { const RipgrepRunResult({required int exitCode, required String stdout, required String stderr, bool timedOut = false}); }`
  - `abstract class RipgrepRunner { Future<RipgrepRunResult> run(RipgrepBinary binary, List<String> args, {required Duration timeout, required int maxOutputBytes}); }`
  - `class ShellRipgrepRunner implements RipgrepRunner { const ShellRipgrepRunner(ShellExecutor shell); }`
  - `class ProcessRipgrepRunner implements RipgrepRunner { const ProcessRipgrepRunner(); }`
  - `class RipgrepLimits { const RipgrepLimits({int defaultLimit = 50, int maxMatches = 1000, Duration timeout = const Duration(seconds: 20), int maxOutputBytes = 20 * 1024 * 1024}); }`
  - `class RipgrepTool extends Tool { const RipgrepTool({required RipgrepRunner runner, required RipgrepBinary binary, ToolResultEviction? eviction, RipgrepLimits limits = const RipgrepLimits()}); }`
  - `FsToolOptions` 新增 `RipgrepRunner? runner`。

- [ ] **Step 1: 写 runner 测试**

`test/ripgrep_runner_test.dart`：

```dart
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_fs_tools/conatus_fs_tools.dart';
import 'package:test/test.dart';

import 'support/fake_shell.dart';

void main() {
  test('ShellRipgrepRunner 用 POSIX 引号拼命令', () async {
    final FakeShellExecutor shell = FakeShellExecutor(
      (ShellExecSpec spec) async => ShellRunResult(
        exitCode: 0,
        stdout: const CollectedOutput(text: 'ok', truncated: false),
        stderr: const CollectedOutput(text: '', truncated: false),
      ),
    );
    final ShellRipgrepRunner runner = ShellRipgrepRunner(shell);

    await runner.run(
      const RipgrepBinary(path: 'rg', source: RipgrepSource.system),
      <String>['--', "a b"],
      timeout: const Duration(seconds: 1),
      maxOutputBytes: 1024,
    );

    expect(shell.lastRequest?.command, "'rg' '--' 'a b'");
  });
}
```

如果 `FakeShellExecutor` 没有 `lastRequest`，在 `test/support/fake_shell.dart` 加一个 `ShellExecRequest? lastRequest` 并在 `resolve` 里记录。

- [ ] **Step 2: 实现 runner**

`ripgrep_runner.dart`：定义 `RipgrepRunResult`、`RipgrepRunner`、`ShellRipgrepRunner`、`ProcessRipgrepRunner`。

- `ShellRipgrepRunner.run`：把 binary 与 args 逐个用 POSIX 单引号包裹，调用 `shell.resolve(ShellExecRequest(command: ..., timeoutMs: ..., stdoutMaxBytes: ...))`，把 `ShellRunResult` 映射成 `RipgrepRunResult`。
- `ProcessRipgrepRunner.run`：用 `Process.start(binary.path, args)`，收集 stdout / stderr，超时 `process.kill()` 并返回 `timedOut: true`；输出超过 `maxOutputBytes` 截断。注释写明：**绕过 `'shell'` 接缝，只适用于本地进程；远程沙箱必须注入自己的 runner。**

- [ ] **Step 3: 改 `RipgrepTool`**

删除 `_command` 字符串拼接与 `_quote`，改为：

```dart
final List<String> args = <String>[
  '--max-count', '${ctx.optional<int>('limit') ?? limits.defaultLimit}',
  if (ctx.has('type')) ...<String>['--type', ctx.str('type')],
  if (ctx.has('context')) ...<String>['-C', '${ctx.integer('context')}'],
  if (filesOnly) '--files-with-matches',
  '--',
  ctx.str('pattern'),
  if (ctx.has('path')) ctx.str('path'),
];
final RipgrepRunResult result = await _runner.run(
  _binary,
  args,
  timeout: limits.timeout,
  maxOutputBytes: limits.maxOutputBytes,
);
```

`timedOut` → `RG_TIMEOUT`；`exitCode == 1` → 无匹配；`exitCode != 0` → `RG_ERROR`；成功走 `_success`，`truncated` 仍按 `limits.maxMatches` 判定。`Tool.timeout` getter 返回 `limits.timeout`，参数描述里的默认值用 `limits.defaultLimit`。

- [ ] **Step 4: 更新 `provideFsTools` 选择 runner**

`FsToolOptions` 加 `this.ripgrep`（`RipgrepBinary?`）与 `this.runner`（`RipgrepRunner?`）。搜索工具段改为：

```dart
if (options.enableSearch) {
  registered.add(GlobTool(fs: resolvedFs, skipDirs: options.skipDirs));
  final ShellExecutor? shell =
      options.shell ?? ctx.get<ShellExecutor>('shell');
  final RipgrepRunner? runner =
      options.runner ?? (shell == null ? null : ShellRipgrepRunner(shell));
  final RipgrepBinary? binary =
      options.ripgrep ?? RipgrepBinary.discover();
  if (runner != null && binary != null) {
    registered.add(RipgrepTool(
      runner: runner,
      binary: binary,
      eviction: options.eviction,
      limits: RipgrepLimits(defaultLimit: options.rgLimit),
    ));
  }
}
```

- [ ] **Step 5: 迁移 ripgrep 测试**

复制 `ripgrep_binary_test.dart`、`ripgrep_tool_test.dart`。`ripgrep_tool_test.dart` 的 `RipgrepTool(shell: shell, ...)` 改为：

```dart
RipgrepTool(
  runner: ShellRipgrepRunner(shell),
  binary: const RipgrepBinary(path: 'rg', source: RipgrepSource.system),
)
```

把 Task 4 删除的“有 shell 且注入 ripgrep → 注册 rg”用例补回 `fs_tools_test.dart`（此时 `provideFsTools` 已接 runner）。另新增断言：pattern `-foo` 出现在 `--` 之后：

```dart
test('pattern 以 - 开头时不会被当成 flag', () async {
  final _FakeRunner runner = _FakeRunner();
  final RipgrepTool tool = RipgrepTool(
    runner: runner,
    binary: const RipgrepBinary(path: 'rg', source: RipgrepSource.system),
  );
  await tool.call(_context(<String, Object?>{'pattern': '-foo'}));
  final int dash = runner.args.indexOf('--');
  expect(dash, isNonNegative);
  expect(runner.args.indexOf('-foo'), greaterThan(dash));
});
```

`ProcessRipgrepRunner` 冒烟测试：`rg --version` 不可用时 `return` 跳过（与现有 ripgrep binary 测试同姿态）。

- [ ] **Step 6: 跑测试并提交**

Run:
```bash
cd packages/conatus_fs_tools
dart test
dart analyze --fatal-infos
```
Expected: 全绿。

```bash
git add packages/conatus_fs_tools
git commit -m "feat(fs_tools): 加 RipgrepRunner 接缝，支持 Windows / 桌面端"
```

---

### Task 7: 迁移 `conatus_code` 到新包

**Files:**
- Modify: `packages/conatus_code/pubspec.yaml`
- Modify: `packages/conatus_code/lib/fs_tools.dart`
- Modify: `packages/conatus_code/lib/diff.dart`
- Modify: `packages/conatus_code/lib/conatus_code.dart`
- Create: `packages/conatus_code/lib/src/tool_result_spill.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_app.dart`
- Modify: `packages/conatus_code/lib/src/coding/coding.dart`
- Modify: `packages/conatus_code/lib/src/tools/code_tools.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_permission_gate.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_controller.dart`
- Modify: `packages/conatus_code/lib/src/story/story_review.dart`
- Modify: `packages/conatus_code/lib/src/diff/diff_source.dart`
- Modify: `packages/conatus_code/lib/src/diff/working_diff.dart`
- Modify: `packages/conatus_code/lib/src/diff/tui_diff_parts.dart`
- Modify: `packages/conatus_code/lib/src/diff/tui_diff_panels.dart`
- Modify: `packages/conatus_code/lib/src/diff/tui_diff_view.dart`
- Delete: `packages/conatus_code/lib/src/fs_tools/`（整个目录）
- Delete: `packages/conatus_code/lib/src/tools/list_files.dart`
- Delete: `packages/conatus_code/lib/src/tools/apply_patch.dart`
- Delete: `packages/conatus_code/lib/src/tools/opencode_patch.dart`
- Delete: `packages/conatus_code/lib/src/tools/opencode_patch_apply.dart`
- Delete: `packages/conatus_code/lib/src/diff/{apply,diff_model,diff_types,diff_parse,diff_parser,diff_builder,diff_paths,unified_diff,line_ops,preview}.dart`
- Delete: `packages/conatus_code/test/fs_tools/{edit_file,fs_tools,glob_tool,read_file,ripgrep_binary,ripgrep_tool,write_file}_test.dart`
- Delete: `packages/conatus_code/test/tools/{apply_patch,list_files}_test.dart`
- Delete: `packages/conatus_code/test/diff/{apply,diff_parser,unified_diff,preview}_test.dart`
- Modify: `packages/conatus_code/test/tui/tui_story_wiring_test.dart`
- Modify: `packages/conatus_code/test/tui/session_rename_fixture.dart`
- Modify: `packages/conatus_code/test/story/story_review_test.dart`
- Modify: `packages/conatus_code/test/story/story_notices_test.dart`
- Modify: `packages/conatus_code/test/story/story_commands_test.dart`
- Modify: `packages/conatus_code/test/story/story_watcher_test.dart`
- Modify: `packages/conatus_code/test/story/story_test.dart`

**Interfaces:**
- Consumes: Task 1–6 的包。
- Produces：`provideFsTools(ctx, options: FsToolOptions(...))` 调用形式；`lib/fs_tools.dart` 兼容入口。

- [ ] **Step 1: 加包依赖**

在 `packages/conatus_code/pubspec.yaml` 的 `dependencies` 与 `dependency_overrides` 中，按现有格式加入 `conatus_diff`、`conatus_fs_tools`，`ref` 先填父仓当前 HEAD：

```yaml
  conatus_diff:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: <parent-sha>, path: packages/conatus_diff}
  conatus_fs_tools:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: <parent-sha>, path: packages/conatus_fs_tools}
```

`<parent-sha>` 用 `git -C ../.. rev-parse HEAD` 的输出。运行 `dart pub get`（在子模块根），预期能解析。

- [ ] **Step 2: 建本地兼容入口**

`lib/src/tool_result_spill.dart` 复制原 `src/fs_tools/spill_dir.dart` 内容（保留 `kNavaProjectDirName` / `toolResultSpillDir`）。

`lib/fs_tools.dart` 改为：

```dart
/// conatus_code 的兼容入口：文件工具已迁到 conatus_fs_tools。
library;

export 'package:conatus_foundation/conatus_foundation.dart'
    show ReadOnlyPathGuard, normalizeReadOnlyPath;
export 'package:conatus_fs_tools/conatus_fs_tools.dart';
export 'src/read_only_policy.dart'
    show
        defaultReadOnlyRoots,
        kGlobalOpenCodePath,
        kOpenCodeDirName,
        kReadOnlyPathCode,
        kReadOnlyPathMessage,
        readOnlyRelativePath,
        readOnlyWritePath;
export 'src/tool_result_spill.dart'
    show kNavaProjectDirName, toolResultSpillDir;
```

`lib/diff.dart` 改为：

```dart
/// `/diff` 数据层入口：公共 diff 类型来自 conatus_diff。
library;

export 'package:conatus_diff/conatus_diff.dart';
export 'src/diff/diff_source.dart' show DiffSource, kDiffNoTurnNotice;
```

- [ ] **Step 3: 更新 `lib/conatus_code.dart` 导出**

把以下本地导出：

```dart
export 'src/diff/apply.dart' show ...;
export 'src/diff/diff_model.dart' show ...;
export 'src/diff/diff_parse.dart' show ...;
export 'src/diff/diff_types.dart' show ...;
export 'src/diff/unified_diff.dart' show ...;
export 'src/diff/preview.dart' show ...;
export 'src/tools/apply_patch.dart' show ApplyPatchTool;
export 'src/fs_tools/spill_dir.dart' show ...;
```

替换为：

```dart
export 'package:conatus_diff/conatus_diff.dart'
    show
        DiffFile,
        DiffHunk,
        DiffOp,
        DiffOpKind,
        DiffScope,
        FileDiff,
        PatchContextException,
        applyDiffFile,
        applyEditText,
        buildUnifiedDiff,
        kMaxDiffLines,
        parseUnifiedDiff,
        splitLines;
export 'package:conatus_fs_tools/conatus_fs_tools.dart'
    show ApplyPatchTool, ListFilesTool, buildApprovalPreview, kPreviewMaxChars;
export 'src/tool_result_spill.dart'
    show kNavaProjectDirName, toolResultSpillDir;
```

同时删除旧的 `export 'src/tools/list_files.dart' show ListFilesTool;`，由上面的 package 导出替代。`src/diff/diff_source.dart` 保留。

- [ ] **Step 4: 更新装配调用**

`lib/src/tui/tui_app.dart` 的 `provideFsTools(app)` 改为：

```dart
provideFsTools(
  app,
  options: FsToolOptions(
    enablePatch: true,
    skipDirs: <String>{...kDefaultSkipDirs, kNavaProjectDirName},
  ),
);
```

`lib/src/coding/coding.dart` 的 `provideFsTools(...)` 改为：

```dart
final List<Tool> registered = provideFsTools(
  ctx,
  options: FsToolOptions(
    fs: fs,
    tools: registry,
    shell: shell,
    eviction: eviction,
    ripgrep: ripgrep,
    rgLimit: rgLimit,
    enableSearch: enableSearch,
    skipDirs: <String>{...kDefaultSkipDirs, kNavaProjectDirName},
  ),
);
```

`lib/src/tools/code_tools.dart` 删除 `ListFilesTool` / `ApplyPatchTool` 的 import 与注册；只保留 git / run 工具，`registered` 从空列表开始。同步改它的文档注释（原来写“注册 list / apply_patch”），并删掉只给 list 用的 `FileSystem? fs` 参数（`tui_app` / 测试都未传它）。

`provideCoding` 原本就不注册 `apply_patch`，所以保持 `enablePatch` 默认 `false`；它会因为 `provideFsTools` 新默认而多注册 `list`（低风险）。如果 `test/coding/provide_coding_test.dart` 里有精确名单断言，更新为包含 `list`。

- [ ] **Step 5: 更新 diff 相关 import**

- `src/diff/diff_source.dart`、`src/diff/working_diff.dart`、`src/diff/tui_diff_parts.dart`、`src/diff/tui_diff_panels.dart`、`src/diff/tui_diff_view.dart`：把 `diff_model.dart` / `diff_parser.dart` / `diff_types.dart` / `unified_diff.dart` / `apply.dart` 的 import 改为 `import 'package:conatus_diff/conatus_diff.dart';`。
- `src/tui/tui_controller.dart`：`../diff/diff_model.dart` → `package:conatus_diff/conatus_diff.dart`。
- `src/story/story_review.dart`：`../diff/apply.dart`、`diff_parse`、`diff_types` → `package:conatus_diff/conatus_diff.dart`。
- `src/tui/tui_permission_gate.dart`：`../diff/preview.dart` → `package:conatus_fs_tools/conatus_fs_tools.dart`。
- `src/xerj/xerj.dart` 与 `src/xerj/xerj_exec.dart`：删除只为 `ToolResultEviction` / 已迁走符号而存在的 `package:conatus_agent/conatus_agent.dart` import（foundation 已导出），让根 `dart analyze --fatal-infos` 恢复绿色。

- [ ] **Step 6: 更新测试调用点**

把以下调用：

```dart
provideFsTools(app, fs: fs, enableSearch: false);
provideFsTools(ctx, fs: fs, enableSearch: false);
provideFsTools(app, enableSearch: false);
```

改为：

```dart
provideFsTools(app, options: FsToolOptions(fs: fs, enableSearch: false));
provideFsTools(ctx, options: FsToolOptions(fs: fs, enableSearch: false));
provideFsTools(app, options: const FsToolOptions(enableSearch: false));
```

涉及文件：`test/tui/tui_story_wiring_test.dart`、`test/tui/session_rename_fixture.dart`、`test/story/story_review_test.dart`、`test/story/story_notices_test.dart`、`test/story/story_commands_test.dart`、`test/story/story_watcher_test.dart`、`test/story/story_test.dart`。

- [ ] **Step 7: 删除已迁出的实现与测试**

删除 Task 7 Files 列表中的 `lib/src/fs_tools/`、`lib/src/tools/{list_files,apply_patch,opencode_patch,opencode_patch_apply}.dart`、`lib/src/diff/` 中除 `diff_source.dart` / `working_diff.dart` / `tui_*` 外的文件，以及对应的已迁出测试。

保留 `test/fs_tools/opencode_snapshot_test.dart`（产品端到端），它通过 `package:conatus_code/fs_tools.dart` 兼容入口继续工作。

- [ ] **Step 8: 跑 nava 测试**

Run:
```bash
cd packages/conatus_code
dart analyze --fatal-infos
dart test
```
Expected: 全绿。常见失败与处理：
- `provideFsTools` 参数错误：漏改某个测试调用点，按 Step 6 模式修。
- `找不到 src/diff/...`：还有文件 import 旧路径，全局搜 `diff/diff_model` / `diff/unified_diff` / `diff/apply`。
- `apply_patch` 未注册：`tui_app` 的 `FsToolOptions(enablePatch: true)` 漏了。

- [ ] **Step 9: 提交子模块**

```bash
cd packages/conatus_code
git add pubspec.yaml lib test
git commit -m "refactor(code): 文件工具改用 conatus_fs_tools"
```

---

### Task 8: 两仓发布、pin ref、重建二进制与全量验证

**Files:**
- Modify: `packages/conatus_code/pubspec.yaml`（pin 后的 ref）
- Modify: 父仓 `packages/conatus_code` gitlink
- Verify: `.github/workflows/integration-test.yml`（consumer probe 可加一行 `FsToolOptions`）

- [ ] **Step 1: 父仓全量校验**

Run:
```bash
cd /Users/fitz/REPO/conatus
git submodule update --init
bash tool/setup_code_filter.sh
bash tool/version.sh
dart pub get
dart format packages/conatus_diff packages/conatus_fs_tools packages/conatus_foundation
dart analyze --fatal-infos
dart test
for d in packages/*/; do
  [ -f "$d/pubspec.yaml" ] || continue
  (cd "$d" && dart test)
done
for d in products/*/; do
  [ -f "$d/pubspec.yaml" ] || continue
  # Flutter 产品（conatus_viva）不是 workspace 成员，跳过；只跑纯 Dart 产品。
  grep -q '^resolution: workspace' "$d/pubspec.yaml" || continue
  (cd "$d" && dart test)
done
dart test test/integration/ --reporter=expanded
```
Expected: 全部通过；`version.sh` 输出所有包 `0.16.0`；`products/conatus_work` 只依赖伞包，仍能解析并测试。

- [ ] **Step 2: 提交并推送父仓，取得 SHA**

```bash
git status
git add packages/conatus_diff packages/conatus_fs_tools packages/conatus_foundation \
  pubspec.yaml lib/conatus.dart README.md AGENTS.md CHANGELOG.md \
  docs/superpowers/specs/2026-10-30-conatus-fs-tools-extraction-design.md \
  docs/superpowers/plans/2026-10-30-conatus-fs-tools-extraction.md
git commit -m "feat(fs_tools): 文件工具与纯 diff 内核上提到父仓"
git push
PARENT_SHA=$(git rev-parse HEAD)
echo "$PARENT_SHA"
```

- [ ] **Step 3: 子模块 pin ref**

```bash
cd packages/conatus_code
bash tool/pin_conatus_refs.sh "$PARENT_SHA"
git add pubspec.yaml
git commit -m "chore(code): pin conatus fs_tools 提取后的 ref"
git push
```

- [ ] **Step 4: 子模块全量验证并重建二进制**

```bash
cd packages/conatus_code
dart pub get
dart analyze --fatal-infos
dart test
bash tool/build_binary.sh
./dist/nava --help
```
Expected: 测试全绿；`nava --help` 正常输出。

- [ ] **Step 5: 父仓同步 gitlink**

```bash
cd /Users/fitz/REPO/conatus
git add packages/conatus_code
git commit -m "chore(code): 同步子模块 gitlink（文件工具上提）"
git push
```

- [ ] **Step 6: workspace 形态验证**

```bash
cd /Users/fitz/REPO/conatus
bash tool/setup_code_filter.sh
dart pub get
dart analyze --fatal-infos
dart test packages/conatus_code
```
Expected: 全绿（这是父仓 CI 的 `workspace-integration` job 做的事）。

- [ ] **Step 7: 更新 consumer probe（可选但推荐）**

在 `.github/workflows/integration-test.yml` 的 consumer probe 里加一行，确认伞包导出链：

```dart
const FsToolOptions opts = FsToolOptions();
print('consumer ok: ${agent.provideAgentLoop} ${team.TeamVoice.noop} ${opts.enableList}');
```

提交：

```bash
git add .github/workflows/integration-test.yml
git commit -m "test(ci): consumer probe 覆盖 conatus_fs_tools 导出"
git push
```

---

### Task 9: 产品层接入验收（`products/conatus_work`）

**Files:**
- Create: `products/conatus_work/test/fs_tools_export_test.dart`
- Modify: `products/conatus_work/pubspec.yaml`（pin 后的 conatus ref）
- Modify: 父仓 `products/conatus_work` gitlink

**Interfaces:**
- Consumes: 伞包 `package:conatus/conatus.dart` 导出的 `FsToolOptions`、`provideFsTools`、`ReadOnlyPathGuard`、`ToolResultEviction`。
- Produces: 产品侧冒烟测试，证明桌面端不需要直接依赖 `conatus_fs_tools`。

- [ ] **Step 1: 写产品侧伞包出口测试**

`products/conatus_work/test/fs_tools_export_test.dart`：

```dart
import 'dart:io';

import 'package:conatus/conatus.dart';
import 'package:test/test.dart';

void main() {
  test('伞包导出文件工具，产品无需直接依赖模块包', () {
    final Directory dir = Directory.systemTemp.createTempSync('conatus-work-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final Context ctx = Context.root();
    provideFileSystemLocal(ctx, fs: LocalFileSystem(cwd: dir.path));
    final ToolRegistry tools = provideTools(ctx);

    final List<Tool> registered = provideFsTools(
      ctx,
      options: const FsToolOptions(enablePatch: true),
    );

    expect(registered.map((Tool t) => t.name),
        containsAll(<String>['read', 'write', 'edit', 'list', 'glob', 'apply_patch']));
    ctx.dispose();
    expect(tools.names, isEmpty);
  });
}
```

Run（在 conatus 仓库根）：
```bash
bash tool/setup_code_filter.sh
dart pub get
cd products/conatus_work && dart test test/fs_tools_export_test.dart
```
Expected: PASS（若失败，检查伞包 `lib/conatus.dart` 是否导出了 `conatus_fs_tools`）。

- [ ] **Step 2: pin 产品 ref 并提交**

```bash
cd products/conatus_work
bash tool/pin_conatus_refs.sh "$PARENT_SHA"
dart format test/fs_tools_export_test.dart
dart analyze --fatal-infos
dart test
git add pubspec.yaml test/fs_tools_export_test.dart
git commit -m "test: 验证伞包导出文件工具"
git push
```

- [ ] **Step 3: 父仓同步产品 gitlink**

```bash
cd /Users/fitz/REPO/conatus
git add products/conatus_work
git commit -m "chore(work): 同步产品子模块 gitlink（文件工具导出验收）"
git push
```

---

## 验收清单

- [ ] `conatus_diff` 零依赖，单测全绿。
- [ ] `conatus_fs_tools` 只依赖 core / diff / foundation / glob，单测全绿。
- [ ] `standalone_consumer_test` 不 import `conatus_agent` 也能装配工具。
- [ ] `conatus_foundation` 导出 `ReadOnlyPathGuard` 与 `ToolResultEviction`。
- [ ] nava 的 `lib/fs_tools.dart` 仍是可用入口；`/rewind`、`/diff`、story 行为不变。
- [ ] `bash tool/version.sh` 通过；父仓 / 子模块 / workspace 三种形态测试全绿。
- [ ] `dist/nava` 已重建并可用。
- [ ] 桌面端（`products/conatus_work`）可按 README 只依赖伞包 `conatus` 接入，无需 `conatus_code` 或直接依赖单个模块包。

## 回滚策略

- 父仓新增包不影响现有消费者；若子模块迁移失败，保留 `lib/fs_tools.dart` 的 re-export，把内部 import 切回旧文件即可，删文件放在最后一步。
- 子模块 pin ref 后若发现回归，回退 `packages/conatus_code` 的 gitlink 与 `pubspec.yaml` ref 到上一个 SHA，重新构建二进制。
