# conatus_checkpoint 提取实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `conatus_code` 的工作区检查点内核与 `/diff` 数据源提取到父仓 `conatus_checkpoint`，让 nava 与桌面端共用；磁盘格式与恢复语义不变。

**Architecture:** 新包只依赖 `conatus_diff` / `conatus_foundation` / `crypto`；`CheckpointOptions` / `CheckpointPolicy` 取代 nava 配置类型与硬编码 `.opencode` 排除面。归档后端、影子 git 后端、管理器、恢复与 diff 数据源整体迁入；nava 保留 TUI 命令、配置映射和 `.opencode` 策略。`RevertService` 本轮留在 nava。

**Tech Stack:** Dart 3.6+、`package:test`、`crypto`、`dart:io`

**Spec:** `docs/superpowers/specs/2026-10-30-conatus-checkpoint-extraction-design.md`

## Global Constraints

- 新包：`version: 0.16.0`、`publish_to: none`、`resolution: workspace`、SDK `^3.6.0`。
- 依赖只允许 `conatus_diff`、`conatus_foundation`、`crypto`；不得依赖 `conatus_agent` / `conatus_code`。
- 新包代码不得出现 `.nava`、`.opencode`、`nocterm`、`sqlite3`、`toml`、`command_shield`；只读/排除前缀由 `CheckpointPolicy` 注入。
- 磁盘格式不变：`<projectDir>/checkpoints/<sessionId>/<sha256>`、`shadow.git`、`index`、旧目录树兼容。
- 恢复语义不变：rsync 式、符号链接 fail-closed、先校验后写。
- 工具/命令行为不变：`/rewind`、`/diff turn`、undo/redo 的 checkpoint 部分。
- 单文件 ≤200、类 ≤150、函数 ≤40、参数 ≤4；无法拆分时加 `// REASON:`。
- 包内相对导入；单引号；声明返回类型；用户文案中文。
- 两仓顺序：父仓包先落地，子模块最后 pin ref + 删副本 + 重建二进制。

## Review Focus

1. 现有检查点归档（含旧目录树格式）升级后仍可 `restore` / `readFile`。
2. `.opencode` 仍不进快照、不被恢复删除；换成别的只读前缀也生效。
3. 恢复遇到工作区外 symlink 时一个文件都不动。
4. `changesBetween` 的 added/modified/deleted/renamed 与 content 读取一致。
5. 影子 git 后端不污染用户仓库，且跨会话复用对象。
6. 上下文/会话重绑时 `bind` 接管、`reset` 重建、`detach` 让在途快照放弃。

---

### Task 1: 新建 `conatus_checkpoint` 包与核心编排

**Files:**
- Create: `packages/conatus_checkpoint/pubspec.yaml`, `analysis_options.yaml`, `README.md`
- Create: `packages/conatus_checkpoint/lib/conatus_checkpoint.dart`
- Create: `lib/src/checkpoint_types.dart`、`checkpoint_changes.dart`、`checkpoint_chain.dart`、`checkpoint_timeline.dart`、`checkpoint_snapshots.dart`、`checkpoint_manager.dart`、`checkpoint_policy.dart`、`checkpoint_options.dart`
- Create: `test/{checkpoint_manager,checkpoint_delta,checkpoint_hash}_test.dart`
- Modify: root `pubspec.yaml`, `lib/conatus.dart`, `README.md`, `AGENTS.md`, `CHANGELOG.md`

**Interfaces:**
- `enum CheckpointBackend { auto, git, archive }`
- `class CheckpointPolicy { const CheckpointPolicy({List<String> ignore = const [], List<String> excludedPrefixes = const [], List<String> readOnlyPrefixes = const []}); }`
- `class CheckpointOptions { const CheckpointOptions({bool enabled = true, int keep = 5, CheckpointBackend backend = CheckpointBackend.auto, CheckpointPolicy policy = const CheckpointPolicy()}); }`
- `CheckpointManager({required CheckpointStore store, required CheckpointOptions options})`
- `CheckpointStore` gains `CheckpointPolicy get policy; List<String> get ignore;`

- [ ] 先复制 manager/types/changes/chain/timeline/snapshots 源码与三个测试。
- [ ] 把 `CheckpointConfig` / `CheckpointBackend` 引用替换为 `CheckpointOptions` / 包内 `CheckpointBackend`；`enabled`/`keep` 从 options 取。
- [ ] 新增 `CheckpointPolicy` 与 `CheckpointOptions`；`CheckpointStore` 加 `policy` getter，`ignore` 保留。
- [ ] 包入口导出这些类型；根包注册（29→30 包 / 14→15 实验性 / 目录 30→31）。
- [ ] 跑 `checkpoint_manager_test` 等三个测试；提交。

### Task 2: 迁入归档后端与路径/扫描/恢复

**Files:**
- Create: `lib/src/checkpoint_paths.dart`（策略/排除）+ `checkpoint_io.dart`（gzip/写回/symlink 校验）
- Create: `checkpoint_scan.dart`、`checkpoint_archive.dart`（必要时拆 `checkpoint_archive_format.dart`）、`checkpoint_store.dart`、`checkpoint_store_archive.dart`、`checkpoint_lookup.dart`、`checkpoint_restore.dart`（可拆 base/delta）、`checkpoint_restore_ops.dart`、`checkpoint_hashes.dart`、`checkpoint_permissions.dart`、`checkpoint_turn_diff.dart`
- Test: `checkpoint_store_test.dart`、`checkpoint_streaming_test.dart`、`checkpoint_restore_escape_test.dart`、`checkpoint_archive_atomic_test.dart`、`checkpoint_permissions_test.dart`、`checkpoint_global_ignore_test.dart`

**Interfaces:**
- `kCheckpointDefaultIgnores` 只保留 `build` / `.dart_tool` / `node_modules`。
- `checkpointExcluded(String rel, String projectRel, CheckpointPolicy policy, {Set<String> extra = const {}})`。
- `checkpointReadablePath(String rel, String projectRel, CheckpointPolicy policy)`。
- `checkpointReadOnlyPath(String rel, List<String> readOnlyPrefixes)`。
- `ArchiveCheckpointStore({required String root, required String projectDir, int keep = 5, CheckpointPolicy policy = const CheckpointPolicy()})`。
- `checkpointWalk(root, projectRel, policy, [extra])`、`checkpointIncluded(..., policy, ...)`。

- [ ] 先移植路径/排除测试，确认 `.opencode` 从包内默认值消失。
- [ ] 迁移归档存储与恢复；把 `store.ignore` 调用改为 `policy`。
- [ ] 拆分超 200 行文件；store 后端若保留整文件，加 `// REASON:`。
- [ ] 跑归档相关测试；提交。

### Task 3: 迁入影子 git 后端与工厂

**Files:**
- Create: `checkpoint_store_git.dart`、`shadow_git_runner.dart`、`shadow_index.dart`、`global_git_ignore.dart`、`git_process_output.dart`、`checkpoint_backend.dart`
- Test: `checkpoint_store_git_test.dart`、`checkpoint_backend_test.dart`、`checkpoint_global_ignore_test.dart`、permissions（shadow-store 权限 + 0700 迁移）用例

**Interfaces:**
- `GitShadowStore({required String root, required String projectDir, int keep = 5, CheckpointPolicy policy = const CheckpointPolicy(), GitRunner? git})`
- `openCheckpointStore({required CheckpointOptions options, required String root, required String projectDir, GitRunner? git})`
- `GitRunner` / `ProcessGitRunner` / `UnavailableGitRunner` 不变。

- [ ] 迁移后端与测试；把 `.opencode` 只读判定改为 `policy.readOnlyPrefixes`。
- [ ] `auto` 探测 git 逻辑保持；无 git 时归档降级。
- [ ] 跑 git 后端测试（无 git 环境跳过）；提交。

### Task 4: 迁入 `/diff` 数据源

**Files:**
- Create: `lib/src/diff_source.dart`、`working_diff.dart`
- Test: `test/diff_source_test.dart`

**Interfaces:**
- `DiffSource({required String workdir, required CheckpointManager checkpoint, required String sessionId, int? turn})`
- `WorkingDiff(String workdir, {bool Function(String path)? acceptsPath})`
- `kDiffNoTurnNotice` 不变。

- [ ] 迁移 `diff_source` / `working_diff`，import 改为 `conatus_diff` + 本地 checkpoint。
- [ ] 迁移 `diff_source_test`；保留 TUI 测试在 nava。
- [ ] 跑测试；提交。

### Task 5: nava 迁移

**Files:**
- Modify: `packages/conatus_code/pubspec.yaml`（加 `conatus_checkpoint`，pin 父仓 SHA）
- Create: `lib/src/checkpoint_config_adapter.dart`
- Modify: `lib/diff.dart`、`lib/conatus_code.dart`、`lib/src/tui/tui_app.dart`、`lib/src/tui/tui_controller.dart`、`lib/src/tui/tui_controller_revert.dart`、`lib/src/tui/tui_controller_redo.dart`、`lib/src/revert/*`、相关测试
- Delete: `lib/src/checkpoint/`、`lib/src/diff/{diff_source,working_diff}.dart`、迁出的测试

- [ ] 加依赖并 pin 父仓 SHA；建配置适配器（`CheckpointConfig` → `CheckpointOptions`，注入 `.opencode` 策略）。
- [ ] 更新 `tui_app` 构造；`CheckpointManager` 改用 options；加一个适配器测试，断言 `CheckpointOptions.policy.readOnlyPrefixes` 含 `.opencode` 与 `.config/opencode`（或按产品实际策略）。
- [ ] 更新 revert / TUI / diff 数据源 import。
- [ ] 更新公共导出；删除旧实现与已迁测试；保留 TUI 命令测试。
- [ ] 跑 `dart analyze --fatal-infos` + `dart test`（已知 2 条 TUI 既有失败）；提交。

### Task 6: 两仓发布与全量验证

- [ ] 父仓 `dart analyze --fatal-infos`、`dart test`、按包测试、集成测试、`tool/version.sh`。
- [ ] 提交父仓；子模块 `pin_conatus_refs.sh`、`dart test`、`build_binary.sh`；提交。
- [ ] 父仓同步 gitlink；workspace 形态验证；记录既有失败。
- [ ] 更新 README/AGENTS/CHANGELOG 的包计数与说明。

## 验收清单

- [ ] 现有归档/影子 git 检查点在迁移后可读、可恢复。
- [ ] `.opencode` 仍只读且不进快照；替换 policy 后行为可配。
- [ ] `DiffSource` / `/diff turn` 行为不变。
- [ ] nava 的 `/rewind`、undo/redo 测试通过（除既有 TUI 失败）。
- [ ] `dist/nava` 重建并可用。
- [ ] 桌面端可通过伞包使用 `CheckpointManager`（后续接入）。

## 已知遗留（不属于本计划范围）

- `workspace-integration` 的 14 个 LSP cwd 失败与 2 个 TUI 失败（见 fs_tools 计划同名小节）。
- `RevertService` 仍在 nava；后续可再迁入本包。
- `checkpoint_store_git` / `checkpoint_store_archive` 若保留整文件，后续单独拆分。
