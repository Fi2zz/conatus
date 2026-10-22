# nava 日常体验对齐 OpenCode V2 — A 组（安全与流程）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现权限 v2、`/undo` `/redo`、`/diff`、formatter-on-edit，四项都不改变零配置行为。

**Architecture:** 权限引擎放 `conatus_agent`，以最外层工具中间件替换现有 `instrumentApproval`；会话绑定只更新 `PermissionScope` 槽位。checkpoint 增加 `bind` / `flush` / 按 session 恢复；undo/redo 在其上做 staged rollback。`/diff` 从 checkpoint store 读取前后内容，非 git 仓库也可用。formatter 复用 lint 的中间件模式，在 linter 内层执行。

**Tech Stack:** Dart 3.11+、`package:test`、`nocterm` TUI、`toml`、现有 `ShellExecutor` 缝。

**Spec:** `docs/superpowers/specs/2026-10-22-nava-opencode-daily-parity-design.md`

## Global Constraints

- `.opencode` 与 `~/.config/opencode` **严格只读**：不创建、不修改、不删除、不改元数据、不写缓存。
- nava 的所有写回只落 `~/.nava/**` 或显式项目数据目录；不写 OpenCode 目录。
- 不配置 `[[permissions]]` / `[formatter]` 时，行为与当前完全一致。
- 单文件 ≤ 200 行、单 class ≤ 150 行、函数体 ≤ 40 行、参数 ≤ 4 个；超限拆文件。
- 每个任务结束跑：`dart analyze --fatal-infos` + 目标测试；提交用 Conventional Commits。
- 不新增运行时依赖；需要 YAML 时复用 `conatus_skill` 的导出，不在 `conatus_code` 直接 import 传递依赖。

## Review Focus

1. **显式 deny + `never_ask`**：用户显式拒绝的规则必须仍然阻断；不能被“永不询问”或 TUI 的 allow-always 绕过。
2. **`/undo` 无 checkpoint / 无历史 / 工作区被外部改动**：必须给出明确提示，不能静默改文件。
3. **`/diff` 在非 git 仓库、二进制文件、超大文件**：必须降级为文件级摘要，不能卡死或崩溃。
4. **formatter 被沙箱拒绝或命令失败**：工具本身仍成功，只追加 skipped，不阻断编辑。
5. **`.opencode` 符号链接写入**：`<workdir>/.opencode/link -> 外部` 不得被任何写入路径穿透。

---

### Task 0: `.opencode` 只读闸门

**Files:**
- Create: `packages/conatus_code/lib/src/fs_tools/read_only_path_guard.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_app.dart`（包住注入的 `fs`）
- Modify: `packages/conatus_code/lib/src/checkpoint/checkpoint_paths.dart`（默认忽略 `.opencode`）
- Modify: `packages/conatus_code/lib/src/story/story_commands.dart`（若直接写盘，先查 guard）
- Test: `packages/conatus_code/test/fs_tools/read_only_path_guard_test.dart`
- Test: `packages/conatus_code/test/fs_tools/opencode_snapshot_test.dart`

**Interfaces:**
- `class ReadOnlyPathGuard implements FileSystem`：
  - `ReadOnlyPathGuard({required FileSystem inner, required List<String> protectedRoots});`
  - 在 `writeText` / `editText` / `remove` 前用 `inner.processPath(target)` 规范化后判定；命中抛 `FsError(FsErrorCode.permissionDenied, 'READ_ONLY_PATH: .opencode 目录只读')`。
  - 读操作全部透传。
- `List<String> defaultReadOnlyRoots(String workdir, {String? home})`：`<workdir>/.opencode` 与 `~/.config/opencode`。
- checkpoint 默认忽略集加入 `.opencode`。

- [ ] **Step 1: Write the failing tests**

```dart
test('write under .opencode is denied', () async {
  final guard = ReadOnlyPathGuard(
    inner: LocalFileSystem(),
    protectedRoots: defaultReadOnlyRoots(dir.path),
  );
  final target = await guard.resolve('${dir.path}/.opencode/commands/x.md');
  expect(() => guard.writeText(target, 'x'), throwsA(isA<FsError>()));
});

test('full session leaves .opencode bytes unchanged', () async {
  final before = _snapshot(dir.path + '/.opencode');
  await _runSessionWithEdits(dir.path);
  expect(_snapshot(dir.path + '/.opencode'), before);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/conatus_code && dart test test/fs_tools`
Expected: FAIL — `ReadOnlyPathGuard` not defined.

- [ ] **Step 3: Implement**

- `ReadOnlyPathGuard` 实现 `FileSystem` 的全部方法：读透传，写前 `_denyIfProtected`；`remove` 对受保护目录拒绝。
- `tui_app` 在 `provideFileSystemLocal` 前包一层；`fs` 工具、story、apply_patch 自动继承。
- `checkpoint_paths.dart` 的默认忽略集加 `.opencode`，确保 rewind 不会写回。
- `story_commands.dart` 若绕过 `fs` 直写，改为先查 guard；否则删掉这条修改。
- 符号链接：`inner.processPath` 已是 canonical；测试覆盖 `.opencode/link -> 外部`。

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/conatus_code && dart test test/fs_tools test/checkpoint`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_code/lib/src/fs_tools/read_only_path_guard.dart packages/conatus_code/lib/src/tui/tui_app.dart packages/conatus_code/lib/src/checkpoint/checkpoint_paths.dart packages/conatus_code/lib/src/story/story_commands.dart packages/conatus_code/test/fs_tools
git commit -m "feat(code): 增加 .opencode 只读闸门"
```

---

### Task 1: 权限规则模型与匹配器

**Files:**
- Create: `packages/conatus_agent/lib/src/permissions/permission_effect.dart`
- Create: `packages/conatus_agent/lib/src/permissions/permission_rule.dart`
- Create: `packages/conatus_agent/lib/src/permissions/permission_verdict.dart`
- Create: `packages/conatus_agent/lib/src/permissions/permission_matcher.dart`
- Modify: `packages/conatus_agent/lib/conatus_agent.dart`（导出）
- Test: `packages/conatus_agent/test/permissions/permission_matcher_test.dart`

**Interfaces:**
- Produces:
  - `enum PermissionEffect { allow, ask, deny }`
  - `class PermissionRule { const PermissionRule({required String action, required String resource, required PermissionEffect effect, String? source}); }`
  - `class PermissionVerdict { final PermissionEffect effect; final PermissionRule? rule; final String action; final List<String> resources; }`
  - `bool permissionPatternMatches(String pattern, String value)`
  - `PermissionRule? lastMatchingRule(List<PermissionRule> rules, String action, String resource)`

- [ ] **Step 1: Write the failing test**

```dart
test('shell pattern trailing " *" matches bare command', () {
  expect(permissionPatternMatches('git status *', 'git status'), isTrue);
  expect(permissionPatternMatches('git status *', 'git status --short'), isTrue);
  expect(permissionPatternMatches('git status *', 'git stash'), isFalse);
});

test('last matching rule wins and deny wins across resources', () {
  final rules = [
    const PermissionRule(action: 'edit', resource: '*', effect: PermissionEffect.allow),
    const PermissionRule(action: 'edit', resource: '*.env', effect: PermissionEffect.deny),
  ];
  expect(lastMatchingRule(rules, 'edit', 'src/a.dart')!.effect, PermissionEffect.allow);
  expect(lastMatchingRule(rules, 'edit', 'config/.env')!.effect, PermissionEffect.deny);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/conatus_agent && dart test test/permissions/permission_matcher_test.dart`
Expected: FAIL — `permissionPatternMatches` not defined.

- [ ] **Step 3: Implement**

`permission_matcher.dart`：把 `*` 转成 `.*`、`?` 转成 `.`，整值锚定；pattern 以 ` *` 结尾时额外接受去掉该后缀的精确值。路径在调用方规范化，匹配器只做字符串通配。

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/conatus_agent && dart test test/permissions/permission_matcher_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_agent/lib/src/permissions packages/conatus_agent/lib/conatus_agent.dart packages/conatus_agent/test/permissions
git commit -m "feat(agent): 增加权限规则模型与通配匹配"
```

---

### Task 2: 权限引擎、作用域与持久化

**Files:**
- Create: `packages/conatus_agent/lib/src/permissions/permission_engine.dart`
- Create: `packages/conatus_agent/lib/src/permissions/permission_scope.dart`
- Create: `packages/conatus_agent/lib/src/permissions/permission_store.dart`
- Modify: `packages/conatus_agent/lib/conatus_agent.dart`
- Test: `packages/conatus_agent/test/permissions/permission_engine_test.dart`
- Test: `packages/conatus_agent/test/permissions/permission_store_test.dart`

**Interfaces:**
- `class PermissionScope { const PermissionScope({this.rules = const [], this.askThreshold, this.agentId = 'build'}); }`
  - `askThreshold == null`：兜底全放行；`ToolRisk.medium`/`high` 对应现有 `alwaysAsk`/`askWhenNeeded`。
- `class PermissionEngine { PermissionVerdict evaluate({required String action, required List<String> resources, required ToolRisk risk, required PermissionScope scope}); }`
- `class PermissionStore { PermissionStore(String path); Future<List<PermissionRule>> load(); Future<void> save(List<PermissionRule> rules); Future<void> add(PermissionRule rule); }`
- 规则合并顺序：`scope.rules` 已由调用方按 config → project → session 排好；引擎只做“最后匹配生效 + 多资源 deny/ask 聚合 + 无命中回退 `askThreshold`”。

- [ ] **Step 1: Write the failing test**

```dart
test('no matching rule falls back to risk threshold', () {
  final engine = PermissionEngine();
  expect(engine.evaluate(action: 'read', resources: ['a'], risk: ToolRisk.low,
      scope: const PermissionScope(askThreshold: ToolRisk.high)).effect, PermissionEffect.allow);
  expect(engine.evaluate(action: 'shell', resources: ['rm -rf x'], risk: ToolRisk.high,
      scope: const PermissionScope(askThreshold: ToolRisk.high)).effect, PermissionEffect.ask);
});

test('explicit deny survives askThreshold null', () {
  final engine = PermissionEngine();
  final scope = PermissionScope(askThreshold: null, rules: [
    const PermissionRule(action: 'shell', resource: 'git push *', effect: PermissionEffect.deny),
  ]);
  expect(engine.evaluate(action: 'shell', resources: ['git push origin main'],
      risk: ToolRisk.high, scope: scope).effect, PermissionEffect.deny);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/conatus_agent && dart test test/permissions/permission_engine_test.dart`
Expected: FAIL — `PermissionEngine` not defined.

- [ ] **Step 3: Implement**

引擎对每个 resource 求最后匹配规则；任一 `deny` 返回 deny，任一 `ask` 返回 ask，否则 allow。无规则命中时按 `risk.index >= askThreshold.index` 返回 ask，否则 allow。`PermissionStore` 原子写临时文件 + rename，`chmod 600`（非 Windows），JSON `{version:1,rules:[...]}`；损坏文件返回空列表。

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/conatus_agent && dart test test/permissions/permission_engine_test.dart test/permissions/permission_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_agent/lib/src/permissions packages/conatus_agent/test/permissions
git commit -m "feat(agent): 增加权限引擎与项目级规则存储"
```

---

### Task 3: 权限中间件接线（最外层）与配置

**Files:**
- Create: `packages/conatus_agent/lib/src/permissions/permission_gate.dart`
- Modify: `packages/conatus_agent/lib/src/approval.dart`（`ApprovalRequest` 增加可选 `action` / `resources` / `rule`）
- Modify: `packages/conatus_agent/lib/src/sub_agent_permission.dart`
- Modify: `packages/conatus_code/lib/src/config/config_schema.dart`
- Modify: `packages/conatus_code/lib/src/config/config_parser.dart`
- Modify: `packages/conatus_code/lib/src/config/config_values.dart`（新增 `readTableList`）
- Modify: `packages/conatus_code/lib/src/tui/tui_app.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_controller.dart:385-399, 1873-1888`
- Modify: `packages/conatus_code/lib/src/tui/tui_permission_gate.dart`
- Test: `packages/conatus_code/test/permissions/permission_config_test.dart`
- Test: `packages/conatus_code/test/permissions/permission_assembly_test.dart`
- Test: `packages/conatus_code/test/tui/tui_permission_test.dart`（补充）

**Interfaces:**
- `Disposer instrumentPermission(Context ctx, {ToolRegistry? tools, PermissionScopeSlot? scope, Approval? approval, Telemetry? telemetry, Duration timeout = const Duration(minutes: 30)})`
- `PermissionScopeSlot`：服务键 `'permissionScope'`，`PermissionScope get current; void set(PermissionScope scope);`
- `PermissionConfig { List<PermissionRule> rules; }`，`ConatusCodeConfig.permissions`
- `ApprovalRequest` 新字段：`String action = ''`、`List<String> resources = const []`、`String? rule`。

- [ ] **Step 1: Write the failing tests**

```dart
test('config parses [[permissions]] in order', () {
  final config = loadConfigFromToml('''
[[permissions]]
action = "shell"
resource = "git push *"
effect = "deny"
''');
  expect(config.permissions.rules.single.effect, PermissionEffect.deny);
});

test('explicit deny blocks even in never_ask', () async {
  // 组装 root Context + tools + PermissionScopeSlot(askThreshold: null, rules: [deny shell])
  // 调 ctx.tools.call(ToolCall(name: 'run_command', arguments: {'command': 'git push'}))
  expect(result.isError, isTrue);
  expect(result.error!.code, 'PERMISSION_DENIED');
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/conatus_code && dart test test/permissions`
Expected: FAIL — `config.permissions` / `PERMISSION_DENIED` not defined.

- [ ] **Step 3: Implement**

1. `instrumentPermission` 在 `provideTools` 之后、hooks/eviction/story/lint 之前注册（最外层）。它读 `PermissionScopeSlot.current`，按工具名映射 action（`rg`→grep、`run_command`/`run_tests`/`run_code`→shell、`web_search`→websearch、`fetch_url`→webfetch、MCP `server__tool`→`server_tool`），resources 由 `pathParams` 取值 / 命令 / URL / query 派生。
2. `allow` → `next()`；`ask` → `ctx.get<Approval>('approval')`，headless 无 gate 时 deny；`deny` → `ToolResult.failure('Blocked by permission rule: ...', error: ToolError('PERMISSION_DENIED', ...))`。
3. 控制器 `_bind` 只更新 slot（session/agent 规则 + 从 `TuiPermissionMode` 映射的 `askThreshold`），不再重挂 `instrumentApproval`；`TuiPermissionGate` 保留为 UI，并展示 `action/resource/rule`。
4. `TuiPermissionGate` 的 allow-always 通过回调把规则写入 `PermissionStore`，规则 pattern 由 action 决定：shell 用命令前缀 + ` *`，path 用目录 glob，MCP 用工具名。
5. `[[permissions]]` 解析：`readTableList('permissions')`；非法 effect/缺字段抛 `ConfigException`。

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/conatus_code && dart test test/permissions test/tui/tui_permission_test.dart`
Run: `cd packages/conatus_agent && dart test test/approval_test.dart test/sub_agent_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_agent/lib/src packages/conatus_code/lib/src packages/conatus_code/test/permissions packages/conatus_code/test/tui/tui_permission_test.dart
git commit -m "feat(code): 权限引擎接入工具管线与配置"
```

---

### Task 4: checkpoint 的 bind / flush / 按会话恢复

**Files:**
- Modify: `packages/conatus_code/lib/src/checkpoint/checkpoint_manager.dart`
- Modify: `packages/conatus_code/lib/src/checkpoint/checkpoint_store.dart`
- Modify: `packages/conatus_code/lib/src/checkpoint/checkpoint_store_archive.dart`
- Modify: `packages/conatus_code/lib/src/checkpoint/checkpoint_store_git.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_controller.dart:1882-1898`
- Test: `packages/conatus_code/test/checkpoint/checkpoint_manager_test.dart`（补充）
- Test: `packages/conatus_code/test/checkpoint/checkpoint_store_test.dart`（补充）
- Test: `packages/conatus_code/test/checkpoint/checkpoint_store_git_test.dart`（补充）

**Interfaces:**
- `Future<String?> CheckpointManager.bind(String sessionId, {String? lastEventId})`：有检查点则 `_sessionId=id; _turn=max(turns)`，不 clear；无则写 turn 0。
- `Future<void> CheckpointManager.flush()`：等待 `_chain`（含在途 recordTurn）。
- `Future<CheckpointRewindResult?> CheckpointManager.restoreTo(String sessionId, int turn)`：按 session 恢复，若绑定同一 session 则同步 `_turn`。
- `Future<List<int>> CheckpointStore.turnsOf(String sessionId)` 已存在，复用。
- 新增：
  - `Future<List<int>?> readFile(String sessionId, int turn, String path)`
  - `Future<List<CheckpointFileChange>> changesBetween(String sessionId, int fromTurn, int toTurn)`
- `class CheckpointFileChange { const CheckpointFileChange({required String path, required String status}); }`（status：`added` / `modified` / `deleted` / `renamed`）。

- [ ] **Step 1: Write the failing tests**

```dart
test('bind adopts existing checkpoints instead of clearing them', () async {
  final manager = CheckpointManager(store: store, config: const CheckpointConfig());
  await manager.reset('s1');
  await manager.recordTurn(lastEventId: 'e1');
  await manager.detach();
  await manager.bind('s1');
  expect(manager.turn, 1);
  expect(manager.list().length, 2);
});

test('readFile returns previous and current content', () async {
  await store.snapshot('s1', 0);
  await store.snapshot('s1', 1);
  expect(await store.readFile('s1', 0, 'a.txt'), isNotNull);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/conatus_code && dart test test/checkpoint/checkpoint_manager_test.dart`
Expected: FAIL — `bind` / `readFile` not defined.

- [ ] **Step 3: Implement**

- `bind` 查 `turnsOf`；非空取 max 作为 `_turn`，不调用 `clearSession`；空则走 `_writeBase`。
- `rewind` / `restoreTo` / `bind` 都经 `_enqueue`；`flush` 直接 `await _chain`。
- `CheckpointStore.readFile`：archive 从归档 entries 取路径；git 用 `git show <commit>:<path>`；不存在返回 `null`。
- `changesBetween`：archive 用两个 manifest 的 `changed/deleted` 合并；git 用 `git diff --name-status <from>:commit <to>:commit`，实现 `CheckpointFileChange(path, status)`。
- 控制器 `_startCheckpoint` 改用 `bind`，修复 `--session` 恢复清空历史的问题。

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/conatus_code && dart test test/checkpoint`
Expected: PASS（git 用例在无 git 环境自动跳过）。

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_code/lib/src/checkpoint packages/conatus_code/lib/src/tui/tui_controller.dart packages/conatus_code/test/checkpoint
git commit -m "fix(code): checkpoint 支持接管已有会话并按会话读取内容"
```

---

### Task 5: `/undo` `/redo`

**Files:**
- Create: `packages/conatus_code/lib/src/revert/revert_stage.dart`
- Create: `packages/conatus_code/lib/src/revert/revert_service.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_controller.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_commands.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui.dart`（消费 prefill）
- Test: `packages/conatus_code/test/revert/revert_service_test.dart`
- Test: `packages/conatus_code/test/tui/tui_undo_command_test.dart`

**Interfaces:**
- `class RevertStage { final String originalSessionId; final String forkSessionId; final int fromTurn; final int toTurn; final String prompt; }`
- `class RevertService { RevertService({required CheckpointManager checkpoint, required SessionStore sessions}); Future<UndoResult> undo(Session current, int steps); Future<RedoResult> redo(RevertStage stage); }`
- `void ConatusTuiController.prefillInput(String text)` + `String? takePrefillInput()`。

- [ ] **Step 1: Write the failing tests**

```dart
test('undo restores files, forks conversation and stages prompt', () async {
  // 两轮会话 + 两次 checkpoint；undo(1)
  expect(result.stage.toTurn, 1);
  expect(File('$dir/a.txt').readAsStringSync(), 'v1');
  expect(result.stage.prompt, contains('第二轮'));
});

test('redo switches back and restores pre-undo files', () async {
  await controller.handleLine('/undo');
  await controller.handleLine('/redo');
  expect(controller.sessionId, originalId);
  expect(File('$dir/a.txt').readAsStringSync(), 'v2');
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/conatus_code && dart test test/revert`
Expected: FAIL — `RevertService` not defined.

- [ ] **Step 3: Implement**

- `/undo [N]`：`await checkpoint.flush()`；目标 `toTurn=max(0,currentTurn-N)`；存在外部改动时弹确认；`restoreTo` 恢复文件；用目标 `lastEventId` fork + adopt + 切换；从原会话 `user/message` 事件取被撤回 prompt；`prefillInput`。
- `/redo`：`restoreTo(originalSessionId, fromTurn)` 先恢复文件，再 `switchSession(original)`；`bind` 会接管原检查点，不会清空。清空 stage。
- 新 prompt 提交前清空 stage（提交语义）。
- checkpoint 关闭：只 fork 对话并提示文件未回滚。
- 命令表加 `undo` / `redo`，帮助文案写清楚“按轮”。

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/conatus_code && dart test test/revert test/tui/tui_undo_command_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_code/lib/src/revert packages/conatus_code/lib/src/tui packages/conatus_code/test/revert packages/conatus_code/test/tui/tui_undo_command_test.dart
git commit -m "feat(code): 增加按轮的 undo/redo 与输入框回填"
```

---

### Task 6: `/diff` 数据层

**Files:**
- Create: `packages/conatus_code/lib/src/diff/diff_model.dart`
- Create: `packages/conatus_code/lib/src/diff/diff_parser.dart`
- Create: `packages/conatus_code/lib/src/diff/diff_source.dart`
- Test: `packages/conatus_code/test/diff/diff_parser_test.dart`
- Test: `packages/conatus_code/test/diff/diff_source_test.dart`

**Interfaces:**
- `enum DiffScope { working, turn }`
- `class FileDiff { final String path; final String status; final List<DiffHunk> hunks; final int additions; final int deletions; }`
- `List<FileDiff> parseUnifiedDiff(String text)`
- `List<FileDiff> diffLines(String path, String? before, String? after, {int maxLines = 5000})`
- `class DiffSource { Future<List<FileDiff>> load(DiffScope scope); }`

- [ ] **Step 1: Write the failing tests**

```dart
test('parses unified diff hunks and counts', () {
  final diffs = parseUnifiedDiff('''
--- a/a.txt
+++ b/a.txt
@@ -1,2 +1,2 @@
-old
+new
 same
''');
  expect(diffs.single.path, 'a.txt');
  expect(diffs.single.additions, 1);
  expect(diffs.single.hunks.single.lines.length, 3);
});

test('line diff handles added and deleted files', () {
  expect(diffLines('new.txt', null, 'a\nb').single.status, 'added');
  expect(diffLines('old.txt', 'a', null).single.status, 'deleted');
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/conatus_code && dart test test/diff`
Expected: FAIL — `parseUnifiedDiff` not defined.

- [ ] **Step 3: Implement**

- 解析 `---/+++/@@`；`\ No newline` 忽略；二进制检测（NUL）返回 `binary` 占位。
- `diffLines` 用 LCS；超过 `maxLines` 只返回文件级 `FileDiff(path, status, hunks: [])` 并带 `truncated` 标记。
- `DiffSource.working` 走 `git diff --no-ext-diff --unified=3` + untracked；无 git 退 `turn`。
- `DiffSource.turn` 用 `CheckpointStore.changesBetween` + `readFile`；前后内容都从 store 取。

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/conatus_code && dart test test/diff`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_code/lib/src/diff packages/conatus_code/test/diff
git commit -m "feat(code): 增加 diff 解析与 checkpoint 数据源"
```

---

### Task 7: `/diff` 视图与命令

**Files:**
- Create: `packages/conatus_code/lib/src/diff/tui_diff_view.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui.dart`（视图路由与按键）
- Modify: `packages/conatus_code/lib/src/tui/tui_commands.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_controller.dart`
- Test: `packages/conatus_code/test/tui/tui_diff_view_test.dart`

**Interfaces:**
- `class TuiDiffView { TuiDiffView({required List<FileDiff> diffs, required DiffScope scope}); }`
- 控制器：`Future<void> openDiff(DiffScope scope)`；`bool diffOpen`；`void closeDiff()`。

- [ ] **Step 1: Write the failing test**

```dart
test('diff view renders file tree and hunk, n/p switch files', () async {
  await tester.pumpComponent(TuiDiffView(diffs: sampleDiffs, scope: DiffScope.working));
  expect(tester.containsText('a.txt'), isTrue);
  expect(tester.containsText('-old'), isTrue);
  await tester.sendKeyEvent(const KeyboardEvent(logicalKey: LogicalKey.keyN));
  expect(tester.containsText('b.txt'), isTrue);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/conatus_code && dart test test/tui/tui_diff_view_test.dart`
Expected: FAIL — `TuiDiffView` not defined.

- [ ] **Step 3: Implement**

- 左侧文件树（path、+/-、状态），右侧 unified diff；`j/k` 滚动、`n/p` 文件、`d` 切源、`m` 标记、`q` 关闭。
- 控制器 `openDiff` 加载 `DiffSource`，空结果提示；`/diff [working|turn]` 缺省 working。
- 只读，无 apply/revert 按钮。
- 视图状态（当前文件、已读集合）保存在 `TuiDiffView`，关闭即丢弃。

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/conatus_code && dart test test/tui/tui_diff_view_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_code/lib/src/diff packages/conatus_code/lib/src/tui packages/conatus_code/test/tui/tui_diff_view_test.dart
git commit -m "feat(code): 增加 /diff 交互式视图"
```

---

### Task 8: formatter-on-edit

**Files:**
- Create: `packages/conatus_code/lib/src/format/formatter_probe.dart`
- Create: `packages/conatus_code/lib/src/format/formatter_service.dart`
- Modify: `packages/conatus_code/lib/src/config/config_schema.dart`
- Modify: `packages/conatus_code/lib/src/config/config_parser.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_app.dart`（在 linter 之后装配）
- Test: `packages/conatus_code/test/format/formatter_probe_test.dart`
- Test: `packages/conatus_code/test/format/formatter_service_test.dart`

**Interfaces:**
- `class FormatterProbe { final List<String> extensions; final List<String> command; final String name; }`
- `FormatterProbe? detectFormatter(String workdir, String path)`
- `class FormatterService { FormatterService({required ShellExecutor shell, required FormatterConfig config, required String workdir}); Future<String?> runIfNeeded(List<String> files); Disposer mount(ToolRegistry tools); }`
- `FormatterConfig { bool enabled; String? command; int timeoutMs; List<String> extensions; }`

- [ ] **Step 1: Write the failing tests**

```dart
test('detects dart formatter for .dart with pubspec', () async {
  final probe = detectFormatter(dir.path, 'lib/a.dart');
  expect(probe!.command, ['dart', 'format']);
});

test('formatter failure does not fail the tool', () async {
  final result = await registry.call(const ToolCall(name: 'write_file', arguments: {'path': 'a.dart', 'content': 'x'}));
  expect(result.isError, isFalse);
  expect(result.content, contains('[Formatter] skipped'));
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/conatus_code && dart test test/format`
Expected: FAIL — `detectFormatter` not defined.

- [ ] **Step 3: Implement**

- 探针：Dart/Go/Rust/Prettier/Ruff；命令在 workdir 执行，`$FILE` 替换绝对路径；跳过 `.opencode/**`。
- `mount` 用 `ToolRegistry.use`，在 linter **之后**注册（更内层），保证 formatter 先于 linter 拿到结果；只处理 `write_file`/`edit_file`/`apply_patch` 成功结果，最多 20 文件。
- 失败/超时/白名单拒绝：追加 `[Formatter] skipped: <原因>`，不改 `isError`。
- 装配点放在 `provideLinter` 之后；配置未启用时 `mount` 返回空 Disposer。

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/conatus_code && dart test test/format`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_code/lib/src/format packages/conatus_code/lib/src/config packages/conatus_code/lib/src/tui/tui_app.dart packages/conatus_code/test/format
git commit -m "feat(code): 增加编辑后 formatter 与配置"
```

---

## 完成标准

- 权限：显式 deny 在三种 `[approval] mode` 下都阻断；零配置审批行为不变。
- undo/redo：文件+对话回滚、redo、新 prompt 提交、无 checkpoint 降级。
- `/diff`：git 与非 git 都能打开；大文件/二进制降级。
- formatter：成功/失败/跳过/顺序正确。
- `dart analyze --fatal-infos` + `cd packages/conatus_agent && dart test` + `cd packages/conatus_code && dart test` 全绿。
