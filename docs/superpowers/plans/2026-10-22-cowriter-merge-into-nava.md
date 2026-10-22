# cowriter 并入 nava 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 cowriter 的故事层、steering、diff apply 增量并入 `conatus_code`（nava），默认关闭故事层，随后归档 cowriter 并从父仓移除该子模块。

**Architecture:** 以 conatus_code 为唯一产品基座；story 作为可选模块（`[story] enabled`，缺省 false）挂到现有工具中间件与 TUI 装配链；steering 与 diff apply 无条件合入。cowriter 不再有代码演进，只留一个 README 归档说明。

**Tech Stack:** Dart 3.10+ / conatus workspace / `package:conatus_doc` / `package:test` / 纯 Dart TUI（nocterm）。

**Spec:** `docs/superpowers/specs/2026-10-22-cowriter-merge-into-nava-design.md`

## Global Constraints

- 所有包 `publish_to: none`；包间依赖 path / git，`conatus_code` 保持 `resolution: workspace`。
- 提交前必须：`dart analyze --fatal-infos` 干净 + 受影响测试通过。
- 单文件 ≤ 200 行、单 class ≤ 150 行、函数体 ≤ 40 行、函数参数 ≤ 4；包内用相对导入。
- 提交信息：Conventional Commits + 中文描述 + scope，如 `feat(code): ...`。
- 改完 `conatus_code` 必须 `bash tool/build_binary.sh` 重建 `dist/nava`。
- 推送顺序：先 `conatus_code`（子模块），再父仓 gitlink。
- 品牌只保留 nava：`~/.nava`、`NAVA_HOME`、`NAVA.md`、`NAVA_VERSION`、`dist/nava`。
- story 默认关闭时，编辑行为、目录落点、prompt 与合并前完全一致。

## Review Focus

1. **默认关闭路径**：用户不配置 `[story]` 时，`write_file` / `edit_file` / `apply_patch` 必须直接落盘，且不创建 `story-log` 目录。Task 5 的关闭用例钉住。
2. **审阅门与审批门顺序**：story 开启且审批模式为 `always_ask` 时，写工具应先成待定补丁、不弹审批。Task 5 的审批计数用例钉住。
3. **headless 直写**：story 开启但走 `-p` 时无人审阅，文件必须真写。Task 6 钉住。
4. **steering 不丢消息**：轮内插话注入后队列清空、不重复投递；轮末兜底仍工作。Task 7 钉住。
5. **配置 fail-closed**：`[story] enabled = "yes"` 这类非法类型必须抛 `ConfigException`，不静默降级。Task 2 钉住。

---

### Task 1: 接入 conatus_doc 并刷新 conatus 钉版

**Files:**
- Modify: `packages/conatus_code/pubspec.yaml`

**Interfaces:**
- Produces: `pubspec.yaml` 中 `conatus_doc` 的 git+path 依赖与 override；全部 `conatus*` ref 指向同一父仓 commit。

- [ ] **Step 1: 取父仓当前 master SHA**

Run:
```bash
git -C /Users/fitz/REPO/conatus rev-parse master
```
Expected: 40 位 SHA，记为 `<SHA>`。

- [ ] **Step 2: 替换 conatus 钉版**

把 `packages/conatus_code/pubspec.yaml` 里所有 `61ab5d9053c71e81ce505538bc8d29fac8c94982` 替换为 `<SHA>`（`dependencies` 与 `dependency_overrides` 两处都要）。

- [ ] **Step 3: 增加 conatus_doc 依赖与 override**

在 `dependencies` 的 `conatus_cron` 之后插入：

```yaml
  conatus_doc:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: <SHA>, path: packages/conatus_doc}
```

在 `dependency_overrides` 的 `conatus_cron` 之后插入同样的 `conatus_doc` 条目。

- [ ] **Step 4: 解析并静态检查**

Run:
```bash
cd /Users/fitz/REPO/conatus/packages/conatus_code
dart pub get && dart analyze --fatal-infos
```
Expected: `dart pub get` 成功；analyze 无输出（干净）。

- [ ] **Step 5: 提交**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(code): 接入 conatus_doc 依赖并刷新 conatus 钉版"
```

（若 `pubspec.lock` 未入库/未变化，只提交 `pubspec.yaml`。）

---

### Task 2: `[story]` 配置（TDD）

**Files:**
- Create: `packages/conatus_code/test/config/config_story_test.dart`
- Modify: `packages/conatus_code/lib/src/config/config_schema.dart`
- Modify: `packages/conatus_code/lib/src/config/config_parser.dart`
- Modify: `packages/conatus_code/lib/src/config/config_loader.dart`

**Interfaces:**
- Produces:
  - `class StoryConfig { const StoryConfig({this.enabled = false}); final bool enabled; }`
  - `ConatusCodeConfig.story`（`StoryConfig`，缺省 `const StoryConfig()`）
  - `ConfigParser._readStory() → StoryConfig`

- [ ] **Step 1: 写失败测试**

创建 `test/config/config_story_test.dart`（沿用 `config_xerj_test.dart` 的 `_writeToml` + `loadConfig` 模式）：

```dart
/// `[story]` 配置解析：缺省关闭、显式开启、非法类型 fail-closed。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

String _writeToml(String content) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-story-cfg');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File file = File('${dir.path}${Platform.pathSeparator}$kConfigFileName');
  file.writeAsStringSync(content);
  return file.path;
}

ConatusCodeConfig _load(String toml) => loadConfig(path: _writeToml(toml));

void main() {
  test('[story] 缺省：enabled 为 false', () {
    expect(_load('[story]\n').story.enabled, isFalse);
  });

  test('[story] enabled = true 被读取', () {
    expect(_load('[story]\nenabled = true\n').story.enabled, isTrue);
  });

  test('[story] enabled 非法类型抛 ConfigException', () {
    expect(
      () => _load('[story]\nenabled = "yes"\n'),
      throwsA(isA<ConfigException>()),
    );
  });

  test('首次启动写入的模板包含 [story] 说明', () {
    final Directory dir = Directory.systemTemp.createTempSync('nava-story-tpl');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String path = '${dir.path}${Platform.pathSeparator}$kConfigFileName';
    loadConfig(path: path);
    final String template = File(path).readAsStringSync();
    expect(template, contains('# [story]'));
    expect(template, contains('enabled = true'));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/fitz/REPO/conatus/packages/conatus_code && dart test test/config/config_story_test.dart`
Expected: 编译失败，`StoryConfig` / `story` 未定义。

- [ ] **Step 3: 加 `StoryConfig`**

在 `config_schema.dart` 的 `LintConfig` 之后加：

```dart
/// 故事层（人机双写）配置；对应 `[story]` 表。
class StoryConfig {
  const StoryConfig({this.enabled = false});

  /// 是否启用故事层：编辑先成待定补丁、`/story` 可用。
  final bool enabled;
}
```

并在 `ConatusCodeConfig` 构造参数与字段中挂上：

```dart
    this.story = const StoryConfig(),
...
  final StoryConfig story;
```

位置放在 `lint` 之后、`background` 之前。

同时把 `StoryConfig` 加入 `lib/conatus_code.dart` 的 `config_schema.dart` export 列表（与 `XerjConfig` / `LintConfig` 同处）。

- [ ] **Step 4: 解析 `[story]`**

在 `config_parser.dart` 的 `parse()` 里 `lint: _readLint(),` 之后加 `story: _readStory(),`，并新增：

```dart
StoryConfig _readStory() {
  final Map<String, dynamic> table = readTable('story');
  return StoryConfig(enabled: readBool(table, 'enabled', false));
}
```

- [ ] **Step 5: 模板加注释段**

在 `config_loader.dart` 的 `kDefaultConfigToml` 里，`[lint]` 段之前插入：

```toml
# 人机双写故事层（可选，默认关闭）：开启后写工具先成待定补丁，
# /story 查看时间轴、apply/reject 待定补丁。关闭时行为与普通编码会话一致。
# [story]
# enabled = true
```

- [ ] **Step 6: 跑测试确认通过**

Run: `dart test test/config/config_story_test.dart`
Expected: 4 个用例全部通过。

- [ ] **Step 7: 提交**

```bash
git add lib/src/config test/config/config_story_test.dart
git commit -m "feat(code): 新增 [story] 配置项（默认关闭）"
```

---

### Task 3: diff apply 纯函数面

**Files:**
- Create: `packages/conatus_code/lib/src/diff/apply.dart`
- Modify: `packages/conatus_code/lib/src/tools/apply_patch.dart:40-100`
- Modify: `packages/conatus_code/lib/src/diff/preview.dart:55-90`
- Create: `packages/conatus_code/test/diff/apply_test.dart`

**Interfaces:**
- Produces:
  - `class PatchContextException implements Exception { const PatchContextException(this.message); final String message; }`
  - `String applyDiffFile(String oldText, DiffFile file)`
  - `String? applyEditText(String text, String oldString, String newString, bool replaceAll)`

- [ ] **Step 1: 写失败测试**

创建 `test/diff/apply_test.dart`：

```dart
/// diff 应用的纯函数面：上下文失配、尾随换行、字面替换。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  test('applyEditText：唯一匹配替换', () {
    expect(applyEditText('a\nb\n', 'b', 'c', false), 'a\nc\n');
  });

  test('applyEditText：多处匹配且 replaceAll=false 返回 null', () {
    expect(applyEditText('a\na\n', 'a', 'b', false), isNull);
  });

  test('applyDiffFile：上下文失配抛 PatchContextException', () {
    final List<DiffFile> files =
        parseUnifiedDiff('--- a/x\n+++ b/x\n@@ -1,1 +1,1 @@\n-old\n+new\n');
    expect(
      () => applyDiffFile('other\n', files.single),
      throwsA(isA<PatchContextException>()),
    );
  });

  test('applyDiffFile：替换保留尾随换行', () {
    final List<DiffFile> files =
        parseUnifiedDiff('--- a/x\n+++ b/x\n@@ -1,1 +1,1 @@\n-old\n+new\n');
    expect(applyDiffFile('old\n', files.single), 'new\n');
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `dart test test/diff/apply_test.dart`
Expected: 编译失败，`applyEditText` / `applyDiffFile` 未定义。

- [ ] **Step 3: 新增 `apply.dart`**

从 cowriter 的 `lib/src/diff/apply.dart` 原样复制到 conatus_code（同一相对路径）。该文件已包含 `PatchContextException`、`applyDiffFile`、`applyEditText` 与私有 `_applyHunk` / `_applyEdit` 语义。

- [ ] **Step 4: 切换调用方**

- `apply_patch.dart`：删除 `_applyHunk` 与 `_PatchContextError`，`on _PatchContextError` 改为 `on PatchContextException`，`_applyFile` 内改为 `await _fs.writeText(target, applyDiffFile(oldText, file));`，并 `import '../diff/apply.dart';`。
- `preview.dart`：删除私有 `_applyEdit`，调用处改为 `applyEditText(...)`，并 `import 'apply.dart';`。

- [ ] **Step 5: 跑相关测试**

Run:
```bash
dart test test/diff/apply_test.dart test/diff/preview_test.dart test/tools/apply_patch_test.dart
```
Expected: 全部通过。

- [ ] **Step 6: 提交**

```bash
git add lib/src/diff/apply.dart lib/src/diff/preview.dart lib/src/tools/apply_patch.dart test/diff/apply_test.dart
git commit -m "refactor(code): diff 应用抽成纯函数面，工具与预览共用"
```

---

### Task 4: 移植 story 源码与测试

**Files:**
- Create: `packages/conatus_code/lib/src/story/*.dart`（11 个文件）
- Create: `packages/conatus_code/test/story/*_test.dart`（8 个文件）
- Modify: `packages/conatus_code/lib/conatus_code.dart`

**Interfaces:**
- Consumes: Task 3 的 `apply.dart`；Task 1 的 `conatus_doc`。
- Produces: `provideStory` / `StoryRecorder` / `StoryPending` / `StoryReviewGate` 等符号，供 Task 5–6 使用。

- [ ] **Step 1: 复制 story 源码**

从 `/Users/fitz/REPO/conatus/packages/cowriter/lib/src/story/` 复制以下 11 个文件到 `lib/src/story/`：

`story.dart`、`story_blocks.dart`、`story_commands.dart`、`story_conflict.dart`、`story_notices.dart`、`story_pending.dart`、`story_render.dart`、`story_review.dart`、`story_scan.dart`、`story_sync.dart`、`story_watcher.dart`。

- [ ] **Step 2: 品牌收口**

- `story_scan.dart`：`kStorySkipDirs` 里的 `'.cowriter'` 改为 `'.nava'`。
- 全部 story 文件内若出现 `cowriter` / `COWRITER` / `.cowriter` 字样，改为对应的 nava 拼写；临时目录前缀 `cowriter-story-` 改为 `nava-story-`。

Run: `grep -rn "cowriter\\|COWRITER" lib/src/story` → 应无输出。

- [ ] **Step 3: 导出公开 API**

在 `lib/conatus_code.dart` 末尾追加（与 cowriter 的 `lib/cowriter.dart` 同款 export 清单）：

```dart
export 'src/story/story.dart' show StoryRecorder, kStoryToolNames, provideStory;
export 'src/story/story_blocks.dart'
    show
        blockBelongsTo,
        blocksOfFile,
        normalizeParagraphText,
        opTextOf,
        paragraphBlockId,
        pathOfBlock,
        renderFileText,
        splitParagraphs;
export 'src/story/story_commands.dart'
    show
        StoryDiscardResult,
        discardStoryPatch,
        renderStoryDiscard,
        renderStoryPreview;
export 'src/story/story_conflict.dart'
    show
        applyPendingOp,
        conflictClose,
        kConflictOpen,
        kConflictSplit,
        mergeConflictVersions,
        readPendingBases;
export 'src/story/story_notices.dart'
    show StoryNotices, StoryFileChange, diffLines, renderEditNotice;
export 'src/story/story_pending.dart'
    show StoryPending, bindStoryPending, renderStoryPending, tryCompileOps;
export 'src/story/story_render.dart'
    show renderStoryTimeline, storyEditedPaths, storyOpLabel, storyPatchTime;
export 'src/story/story_review.dart' show StoryReviewGate, previewEditedOps;
export 'src/story/story_scan.dart' show kStorySkipDirs, kStoryTextExtensions;
export 'src/story/story_sync.dart'
    show
        anchorForNewFile,
        buildSyncOps,
        kParagraphLimit,
        syncFileOps,
        wholeFileOps;
export 'src/story/story_watcher.dart' show StoryWatcher;
```

同时把 `apply.dart` 也加进 barrel：

```dart
export 'src/diff/apply.dart'
    show PatchContextException, applyDiffFile, applyEditText;
```

- [ ] **Step 4: 复制 story 测试**

从 cowriter `test/story/` 复制 8 个测试文件到 conatus_code `test/story/`，并做两处替换：

- `package:cowriter/` → `package:conatus_code/`
- `cowriter` → `nava`（仅注释与临时目录名前缀）

Run: `grep -rn "cowriter" test/story` → 应无输出。

- [ ] **Step 5: 静态检查与测试**

Run:
```bash
dart analyze --fatal-infos
dart test test/story
```
Expected: analyze 干净；8 个 story 测试文件全部通过。

- [ ] **Step 6: 提交**

```bash
git add lib/src/story lib/conatus_code.dart test/story
git commit -m "feat(code): 移植故事层源码与测试（默认不装配）"
```

---

### Task 5: TUI 装配、`/story` 与开关

**Files:**
- Modify: `packages/conatus_code/lib/src/tui/tui_app.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_controller.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_commands.dart`
- Modify: `packages/conatus_code/bin/conatus_code.dart`
- Create: `packages/conatus_code/test/tui/tui_story_wiring_test.dart`

**Interfaces:**
- Consumes: Task 2 `StoryConfig`；Task 4 `provideStory` / `StoryPending`。
- Produces:
  - `ConatusTuiRuntime.create({..., StoryConfig? story})`
  - `final bool storyEnabled`（`ConatusTuiRuntime`）
  - `ConatusTuiController({..., bool storyEnabled = false})`

- [ ] **Step 1: 写失败测试**

创建 `test/tui/tui_story_wiring_test.dart`，覆盖三条：

1. `storyEnabled: false`：`controller.start()` 后经 `app.tools.call(const ToolCall(name: 'write_file', arguments: {'path': 'a.txt', 'content': 'hello'}))` 调写工具，断言 `a.txt` 内容为 `hello`，结果文本不含「待定补丁」。
2. `storyEnabled: true`：同样的调用返回成功且文本含「待定补丁」，`a.txt` 不存在；随后 `await controller.handleLine('/story apply 1')`，`a.txt` 出现且内容为 `hello`。
3. 审阅门顺序（不经 controller）：建 Context + `provideTools` + `provideFsTools(enableSearch: false)` + `provideSessionLog(InMemorySessionLog())` + `provideSessions`，先 `await provideStory(ctx, sessionId: 's1', session: session, review: true)`，再 `instrumentApproval(ctx, approval: AutoApproval(true), threshold: ToolRisk.medium)`；调 `write_file` 后断言 `approval.requests == 0` 且结果为待定补丁。
4. 运行时目录：`ConatusTuiRuntime.create(baseDir: temp, story: const StoryConfig(enabled: false), llm: <stub>)` 后断言 `$temp/story-log` 不存在；改成 `enabled: true` 后存在。

装配参考 `test/tui/tui_controller_test.dart` 的 `_build`：`provideTools`、`provideFileSystemLocal`、`provideFsTools(enableSearch: false)`、`provideSessionLog`（`InMemorySessionLog`）、`provideSessions`，再构造 controller。写工具落点用临时目录，`addTearDown` 删除。

- [ ] **Step 2: 跑测试确认失败**

Run: `dart test test/tui/tui_story_wiring_test.dart`
Expected: 编译失败，`storyEnabled` 参数不存在。

- [ ] **Step 3: 运行时增加 story 开关**

`tui_app.dart`：

- `ConatusTuiRuntime.create` 增加参数 `StoryConfig? story`；
- 构造函数增加 `required this.storyEnabled`，字段 `final bool storyEnabled;`；
- 在 `create` 内 `storyEnabled: story?.enabled ?? false`；
- `provideSessionLog(... story-log ...)` 整段包在 `if (storyEnabled) { ... }` 内；
- `story-ops` prompt section 包在 `if (storyEnabled) { ... }` 内；
- `steering` prompt section 无条件保留；
- 构造 controller 时传 `storyEnabled: storyEnabled`。

- [ ] **Step 4: bin 传入配置**

`bin/conatus_code.dart`：`ConatusTuiRuntime.create(...)` 调用增加 `story: config.story`。

- [ ] **Step 5: 控制器接线**

`tui_controller.dart`：

- 构造函数增加 `this.storyEnabled = false`，字段 `final bool storyEnabled;`（或用私有 `_storyEnabled`，构造参数 `bool storyEnabled = false`）。
- `_bind` 里：

```dart
    if (storyEnabled) {
      await provideStory(ctx, sessionId: id, session: session, review: true);
    }
    _agent = ctx.agentLoop;
    _agent?.steering = _takeQueuedForSteering;
```

- `_handleStory` 开头：

```dart
    if (!storyEnabled) {
      transcript.add(
        TuiRole.system,
        '故事层未启用：在 config.toml 设 [story] enabled = true 后重启。',
      );
      return;
    }
```

- 移植 `kStoryUsage`、`_handleStory` / `_runStorySub` / `_previewStory` / `_discardStory` / `_forkStory` / `_applyStoryPending` / `_rejectStoryPending` / `_storyPending` 与 `_takeQueuedForSteering`（逐段对应 cowriter 的同名实现）。
- 保留 nava 现有 `/commit`、`/review` 分支与 `_handleCommit` / `_handleReview`，不要删除。

- [ ] **Step 6: 注册 `/story` 命令**

`tui_commands.dart`：在 `init` 之后插入：

```dart
  TuiCommand(
    name: 'story',
    description:
        '故事线（人机双写）：时间轴 / preview / discard / fork / pending / apply / reject',
    argHint: '[子命令]',
  ),
```

- [ ] **Step 7: 跑测试与静态检查**

Run:
```bash
dart test test/tui/tui_story_wiring_test.dart test/tui/tui_commands_test.dart
dart analyze --fatal-infos
```
Expected: 全绿、analyze 干净。

- [ ] **Step 8: 提交**

```bash
git add lib/src/tui bin/conatus_code.dart test/tui/tui_story_wiring_test.dart
git commit -m "feat(code): story 层接入 TUI，[story] enabled 默认关闭"
```

---

### Task 6: headless 开关

**Files:**
- Modify: `packages/conatus_code/lib/src/headless/headless_runner.dart`
- Create: `packages/conatus_code/test/headless/headless_story_test.dart`

**Interfaces:**
- Consumes: `ConatusTuiRuntime.storyEnabled`（Task 5）。
- Produces: `runHeadless` 在开启 story 时仍直写。

- [ ] **Step 1: 写失败测试**

`test/headless/headless_story_test.dart`：建 runtime 时传 `story: const StoryConfig(enabled: true)`，脚本 provider 第一轮返回一个 `write_file` 工具调用、第二轮返回文本；`runHeadless` 后断言目标文件内容已写入（不走待定补丁）。测试装配参考 `test/headless/headless_runner_test.dart`。

- [ ] **Step 2: 跑测试确认失败**

Run: `dart test test/headless/headless_story_test.dart`
Expected: 失败（story 未装配或没有 `storyEnabled` 字段）。

- [ ] **Step 3: 加开关**

`headless_runner.dart`：

```dart
  if (runtime.storyEnabled) {
    await provideStory(ctx, sessionId: session.id, session: session);
  }
```

替换现有无条件调用（review 缺省 false，保持直写）。

- [ ] **Step 4: 跑测试**

Run: `dart test test/headless/headless_story_test.dart test/headless/headless_runner_test.dart`
Expected: 全部通过。

- [ ] **Step 5: 提交**

```bash
git add lib/src/headless test/headless/headless_story_test.dart
git commit -m "feat(code): headless 按 [story] 开关装配故事层，保持直写"
```

---

### Task 7: steering 与输入队列

**Files:**
- Modify: `packages/conatus_code/lib/src/tui/tui_controller.dart`
- Create: `packages/conatus_code/test/tui/tui_steering_test.dart`
- Modify: `packages/conatus_code/test/tui/tui_message_queue_test.dart`

**Interfaces:**
- Consumes: `AgentLoop.steering`（`Future<List<String>> Function()`）；Task 4 的 `StoryNotices`。
- Produces: `_takeQueuedForSteering` 合并 notices + 队列；轮末兜底路径保留。

- [ ] **Step 1: 移植测试**

复制 cowriter `test/tui/tui_steering_test.dart` 与 `test/tui/tui_input_queue_test.dart` 中**尚未被 `tui_message_queue_test.dart` 覆盖**的断言到 conatus_code：改为 `package:conatus_code/tui.dart` 导入，去掉重复用例（同一行为只保留一处）。

Run: `dart test test/tui/tui_steering_test.dart` → 预期编译失败（`steering` 未接线）。

- [ ] **Step 2: 实现 steering**

- `_bind` 里 `_agent?.steering = _takeQueuedForSteering;`（Task 5 已加，确认存在）。
- 加入 `_takeQueuedForSteering`：先取 `_sessionCtx?.get<StoryNotices>('storyNotices')?.drain()`，再取 `_queue` 全部文本；两者皆空返回空列表；否则清空队列、`_refresh()`、返回 `[...notices, ...texts]`。
- 轮末队列投递处补注释「多数时候队列已被 steering 取空，这里是兜底路径」。

- [ ] **Step 3: 跑测试**

Run:
```bash
dart test test/tui/tui_steering_test.dart test/tui/tui_message_queue_test.dart test/tui/tui_input_queue_test.dart
```
Expected: 全绿。

- [ ] **Step 4: 提交**

```bash
git add lib/src/tui/tui_controller.dart test/tui
git commit -m "feat(code): 排队消息轮内注入（steering），轮末保留兜底"
```

---

### Task 8: 文档

**Files:**
- Modify: `packages/conatus_code/README.md`
- Modify: `packages/conatus_code/CHANGELOG.md`
- Create: `packages/conatus_code/docs/story.md`

- [ ] **Step 1: 写 `docs/story.md`**

从 cowriter README 的「人机双写故事层」相关段落裁剪：补丁模型（一次编辑 = 一个补丁）、`/story` 子命令、`[story] enabled` 开关、数据落点（`~/.nava/projects/<工作区>/story-log`）、已知边界（锚点批注 / supersede 未实现）。所有 `cowriter` 改 `nava`，删除写作产品定位。

- [ ] **Step 2: README 增小节**

在「特性」中加一条「故事层（可选，默认关闭）」；在「配置」中加 `[story]` 表说明与 `docs/story.md` 链接。

- [ ] **Step 3: CHANGELOG**

在 `## [未发布]` 顶部加：

```markdown
- **故事层（可选）**：从 cowriter 并入故事层——编辑即补丁、事前审阅、`/story`
  时间轴与分叉；`[story] enabled` 默认 false，关闭时行为与既有编码会话一致。
  同时合入轮内 steering、diff 应用纯函数面。
```

- [ ] **Step 4: 提交**

```bash
git add README.md CHANGELOG.md docs/story.md
git commit -m "docs(code): 补充可选故事层与 [story] 配置说明"
```

---

### Task 9: 全量验证、构建与推送

- [ ] **Step 1: 全量检查**

Run:
```bash
cd /Users/fitz/REPO/conatus/packages/conatus_code
dart format .
dart analyze --fatal-infos
dart test
```
Expected: analyze 干净；所有测试通过（原 909 + 新增）。

- [ ] **Step 2: 重建二进制**

Run:
```bash
bash tool/build_binary.sh
./dist/nava --version
```
Expected: 输出 `nava 0.1.0`（或不含 `dev` 的版本号）。

- [ ] **Step 3: 冒烟**

Run（临时配置目录）：
```bash
NAVA_HOME=$(mktemp -d) ./dist/nava --version
```
Expected: 正常输出，且临时目录内生成 `config.toml`；模板含 `# [story]`。

- [ ] **Step 4: 提交遗留改动并推送**

```bash
git status --short
git add -A
git commit -m "chore(code): 全量回归通过并重建二进制"   # 仅当有遗留改动
git push
```

---

### Task 10: cowriter README 归档并 archive

**Files:**
- Modify: `packages/cowriter/README.md`

- [ ] **Step 1: README 顶部写归档说明**

在标题之前插入：

```markdown
> **已归档（2026-10-22）**：本项目已并入 [nava（conatus_code）](https://github.com/Fi2zz/conatus_code)，
> 不再接受改动。归档原因：双份约 4 万行代码 95% 重合，维护成本高于收益；故事层、
> 轮内 steering 与 diff 应用重构已移植到 nava，并在 nava 上以 `[story] enabled`
> 默认关闭的形式保留。迁移：`~/.cowriter/config.toml` → `~/.nava/config.toml`，
> `~/.cowriter/projects/<工作区>/story-log` 保持原样（nava 的 story-log 在其项目数据目录下），
> `COWRITER.md` → `NAVA.md`。问题请提到 conatus 仓库。
```

- [ ] **Step 2: 提交并推送**

```bash
git add README.md
git commit -m "docs: 归档说明——并入 nava，本仓库停止维护"
git push
```

- [ ] **Step 3: GitHub archive**

Run: `gh repo archive Fi2zz/cowriter --yes`
Expected: 成功；若 gh 未登录或不可用，改为在 GitHub 网页 Settings → Archive 手动归档，并在交付说明中记录。

---

### Task 11: 父仓移除 cowriter 子模块

**Files:**
- Modify: `.gitmodules`
- Delete: `packages/cowriter`（gitlink 与本地目录）
- Modify: `tool/setup_code_filter.sh`
- Modify: `AGENTS.md`
- Modify: `README.md`

- [ ] **Step 1: 移除子模块**

Run:
```bash
cd /Users/fitz/REPO/conatus
git submodule deinit -f packages/cowriter
git rm -f packages/cowriter
rm -rf .git/modules/packages/cowriter
```

- [ ] **Step 2: 清理 `.gitmodules` 与脚本**

删除 `.gitmodules` 的 cowriter 段；`tool/setup_code_filter.sh` 的 `for target in packages/conatus_code packages/cowriter; do` 改为只遍历 `packages/conatus_code`。

- [ ] **Step 3: 更新文档**

- `AGENTS.md` §2 子模块从 ×2 改 ×1（删除 cowriter 行）；§7 删除 cowriter 二进制说明；§10 删除 cowriter 现状段落。
- 根 `README.md` 删除「packages/cowriter 同为独立子模块」段落及 fork 说明。

- [ ] **Step 4: 验证 workspace**

Run:
```bash
dart pub get
dart analyze --fatal-infos
dart test
```
Expected: 全部通过；`dart pub get` 不再解析 cowriter。

- [ ] **Step 5: 提交并推送父仓**

```bash
git add -A
git commit -m "chore(code): 移除 cowriter 子模块（并入 nava 后归档）"
git push
```

---

### Task 12: 最终验收

- [ ] **Step 1: 确认子模块状态**

Run:
```bash
git -C /Users/fitz/REPO/conatus/packages/conatus_code log --oneline -3
git -C /Users/fitz/REPO/conatus/packages/conatus_code status --short
```
Expected: 工作区干净，最新提交为 story 合并相关。

- [ ] **Step 2: 对照 spec 验收清单逐项勾选**

检查 spec §8 的 10 项：`[story]` 默认 false、关闭无副作用、开启可用、headless 直写、steering 测试、analyze、全量测试、二进制、父仓无子模块、cowriter README 归档。

- [ ] **Step 3: 汇报结果**

列出：合并提交 SHA、测试数量、二进制路径与版本、cowriter 归档提交 SHA、父仓清理提交 SHA。
