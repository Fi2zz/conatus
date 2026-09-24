# nava checkpoint/rewind Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 nava 加上工作区文件级检查点/回滚：每轮收口后对 workdir 做文件快照（初始 turn 0 一份），`/rewind [N]` 一键恢复到 N 轮前的文件状态。v1 只回滚文件、不动对话（对话回滚为 v2，见 spec「已知边界与后续」）。

**Architecture:** 全部改动在 `packages/conatus_code` 子模块。新增 `lib/src/checkpoint/` 两层：`CheckpointStore`（纯文件系统快照/恢复/prune/list/manifest，dart:io 直连、不依赖 controller）与 `CheckpointManager`（每会话轮次计数 + `/rewind` 编排）。配置层新增 `[checkpoint]` 表（enabled/keep/ignore）。控制器 `_afterTurn` 收口后快照；`/rewind` 走用户命令不挂审批。恢复走 dart:io 直连（应用级信任域），不经过 fs 接缝。

**Tech Stack:** Dart 3.10+、dart:io、`toml` 0.18（config 层复用既有模式）。

**Spec:** `docs/superpowers/specs/2026-09-24-conatus-code-checkpoint-rewind-design.md`

## Global Constraints

- 仓库 AGENTS.md 硬约束：函数体 ≤40 行、class ≤150 行、单文件 ≤200 行（测试文件不受限）、函数参数 ≤4（超限加 `// REASON:`）、每函数 if/else/switch ≤3（按语句级计）、嵌套 ≤2、禁嵌套三元、优先 early return。
- 布尔命名禁 `is/has/can/should` 前缀；函数名「动词 + 名词」；包内相对导入；单引号；中文文档注释。
- 仓库未强制 `dart format`——不要跑它；风格对齐周围代码。
- `packages/conatus_code` 是独立 git 子模块：实现与提交都在子模块内（`feat(code): ...`），父仓库只提交 gitlink（`chore(code): 同步子模块 gitlink（<简述>）`）。
- 每个 Task 末尾：`dart analyze` + 相关测试通过后提交一次。
- Milestone 末尾：`bash tool/build_binary.sh` 重建 `dist/nava`，再提交父仓库 gitlink。
- 子模块工作区有**用户未提交的 UI 改动**（`tui.dart`/`tui_chrome.dart`/`tui_permission.dart`/`tui_views.dart`/`tui_status_bar_test.dart`/`example/fitness_plan.dart`/`tool/_dump.dart`）——**只 add 自己碰的文件，勿 `git add -A`**。
- 全量 `dart test` 有 7 个用户 UI WIP 的红测试（预期），不作为回归；以「我改动的文件对应的测试」为提交门禁。

## Review Focus

以下失败模式用户会撞上，每条在对应 Task 里钉住：

1. **`/rewind` 时无检查点**（`[checkpoint] enabled=false` 或尚无任何轮次）→ 提示「没有可回滚的检查点」，不报错（Task 4 钉）。
2. **`/rewind N` 超出可用轮次** → 钳制到最早检查点，提示实际回滚到第几轮（Task 4 钉）。
3. **恢复撞上「当前有而检查点没有」的文件** → 删除（rsync 语义），报告里列出删除数（Task 1 钉）。
4. **快照失败不打断轮次**：只提示「检查点保存失败」，主链路继续（Task 3 钉）。
5. **busy（有在途轮次）时 `/rewind`** → 拒绝并提示稍候（Task 4 钉）。
6. **符号链接文件** → 快照跳过（防逃逸）；恢复也不触碰（Task 1 钉）。
7. **`[checkpoint] keep=0`** → 不限制保留数（Task 1 钉）。
8. **恢复不改对话** → 追加 system 说明「文件已回滚到第 N 轮」，会话/transcript 其余不变（Task 4 钉）。

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `lib/src/checkpoint/checkpoint_store.dart` | **新**：`CheckpointStore`（snapshot / restore / prune / list / manifest，dart:io） |
| `lib/src/checkpoint/checkpoint_manager.dart` | **新**：`CheckpointManager`（每会话轮次计数、绑定/解绑、rewind 编排） |
| `lib/src/config/config_schema.dart` | `CheckpointConfig`（enabled/keep/ignore） |
| `lib/src/config/config_parser.dart` | `_readCheckpoint()` |
| `lib/src/config/config_loader.dart` | 模板 `[checkpoint]` 注释示例 |
| `lib/src/tui/tui_controller.dart` | 持 manager；`_afterTurn` 快照；`/rewind` 命令 |
| `lib/src/tui/tui_commands.dart` | `/rewind` 表项 |
| `lib/conatus_code.dart` | 导出 checkpoint 公开面 |
| `test/checkpoint/checkpoint_store_test.dart` | **新**：store 全路径 |
| `test/checkpoint/checkpoint_manager_test.dart` | **新**：轮次计数与编排 |
| `test/tui/tui_rewind_command_test.dart` | **新**：控制器侧命令行为 |
| `README.md` / `CHANGELOG.md` | 配置示例与变更记录 |

---

## Task 1: `CheckpointStore`（纯文件系统层）

**Files:** New `lib/src/checkpoint/checkpoint_store.dart`；Test `test/checkpoint/checkpoint_store_test.dart`

- [x] `CheckpointStore(root, projectDir, {keep = 5, ignore = const <String>[]})`：
  - `snapshot(sessionId, turn, {String? excludePrefix})` → 建 `<projectDir>/checkpoints/<sessionId>/<turn>/`，遍历 root（递归 dart:io）复制文件保留相对路径；跳过：`<projectDir>` 整树、`.git` 整树、`[ignore]` 前缀匹配、符号链接；写 `manifest.json`（`{'turn': n, 'files': [<relPath>...]}`）。
  - `restore(sessionId, turn)` → 读 manifest：清单文件复制回 root（覆盖）；root 中不在清单的相对文件删除；返回 `(restored, deleted)` 计数。
  - `prune(sessionId)` → 保留最近 `keep` 个 turn 目录（`keep<=0` 不限）；`snapshot` 内调用。
  - `list(sessionId)` → 现有 turn 序号升序 + 各目录文件数。
  - 快照前 `prune`。
- [x] 测试（真实临时目录）：
  - 快照排除 `.git` / `.conatus` / ignore 前缀 / 符号链接；manifest 与目录一致；
  - restore：修改（覆盖）、新增（当前有清单无 → 删）、删除（清单有当前无 → 补回）三类；
  - prune 保留最近 N；`keep=0` 不限；
  - 空 workdir 快照正常；
  - `enabled` 由 manager 控制，store 不感知。
- [x] `dart analyze` + 该测试通过，子模块提交 `feat(code): CheckpointStore 文件快照/恢复/prune（checkpoint Task 1）`。

## Task 2: config `[checkpoint]` 表

**Files:** Modify `config_schema.dart` / `config_parser.dart` / `config_loader.dart`；Test `test/config/config_checkpoint_test.dart`

- [x] `CheckpointConfig`（`enabled=true` / `keep=5` / `ignore=[]`）+ `ConatusCodeConfig.checkpoint`。
- [x] `_readCheckpoint()`：`readBool('enabled', true)`、`readNonNegativeInt('keep', 5)`、`readStringList('ignore')`；`keep` 为负抛 `ConfigException`。
- [x] 模板加 `[checkpoint]` 注释示例。
- [x] 测试：缺省值、完整解析、`keep=-1` 报错、`keep=0` 合法（不限）、`ignore` 列表。
- [x] `dart analyze` + 通过，子模块提交 `feat(code): config 解析 [checkpoint] 表（checkpoint Task 2）`。

## Task 3: `CheckpointManager` + 控制器快照接线

**Files:** New `lib/src/checkpoint/checkpoint_manager.dart`；Modify `tui_controller.dart`；Test `test/checkpoint/checkpoint_manager_test.dart` + 补 `test/tui/tui_runtime_assembly_test.dart` 装配例

- [x] `CheckpointManager`：构造收 `(workdir, projectDir, CheckpointConfig)`；`reset()`（绑定会话时调，轮次归 0）；`recordTurn()`（收口后调：turn++ 后 store.snapshot）；`rewind(int n)` → 返回目标 turn 与 `(restored, deleted)`；`available()` → store.list；`enabled` 由 config 决定。
- [x] 控制器：`_bind` 时按 `'checkpointManager'` 服务（根上下文 create 提供）`reset()`；`_afterTurn` 末尾（recovery 快照之后）`recordTurn()`——快照失败只提示不抛（Review Focus #4）。
- [x] `ConatusTuiRuntime.create`：新增 `workdir`（已有）+ `checkpointConfig` 形参，装配 `CheckpointManager` 到 `'checkpointManager'`；bin 传 `config.checkpoint`。
- [x] 测试：manager 轮次递增、turn 0 初始快照存在、`rewind` 目标钳制、`enabled=false` 时 recordTurn 不写盘。
- [x] `dart analyze` + 通过，子模块提交 `feat(code): CheckpointManager 与控制器每轮快照（checkpoint Task 3）`。

## Task 4: `/rewind` 命令 + 文档

**Files:** Modify `tui_commands.dart` / `tui_controller.dart` / `lib/conatus_code.dart` / `README.md` / `CHANGELOG.md`；Test `test/tui/tui_rewind_command_test.dart`

- [x] `/rewind [N]` / `/rewind list`：`list` 列出可用检查点；`N` 缺省 1；`N<1` 按 1；超出钳制到最早并提示实际 turn（Review Focus #2）；无检查点提示（#1）；busy 拒绝（#5）。
- [x] 恢复成功后追加 system 说明「文件已回滚到第 N 轮（恢复 X、删除 Y 个文件），会话与对话未改动」（Review Focus #8）；恢复失败不触碰文件并提示。
- [x] 导出 `CheckpointStore` / `CheckpointManager` / `CheckpointConfig` 公开面。
- [x] README「配置」节 + 新增「检查点与回滚（`/rewind`）」小节；CHANGELOG 记录。
- [x] 测试：真实临时 workdir + projectDir 下 `/rewind 1` 恢复文件状态、`/rewind list` 输出、无检查点提示、busy 拒绝。
- [x] `dart analyze` + 相关测试通过 + `bash tool/build_binary.sh`，子模块提交 `feat(code): /rewind 回滚工作区（checkpoint Task 4）`。

## 收尾

- 父仓库 `chore(code): 同步子模块 gitlink（checkpoint/rewind）` + push。
- 更新 `docs/superpowers/plans/2026-09-24-conatus-code-feature-gaps.md` 的 spec #3 状态；HANDOFF-21 下一步表勾掉该项。

## v2（本计划不覆盖，已文档化）

- 对话回滚：`Session.fork` + `SessionStore.adopt`（需 conatus_foundation 加 additive 方法）+ fork 会话 id 规范化。单独出设计/计划。
- delta 快照优化（大工作区成本）；硬链接方案已否决（原地写共享 inode）。
