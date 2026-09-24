# nava 三期（后台任务 / 消息队列 / delta 快照）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 三期三件事：A 后台任务执行器（消费 `[background]` 配置与 `ShellExecutor.start` 能力缝）、B 消息队列（busy 时排队追问）、C delta 快照（checkpoint 只存变化文件）。

**Architecture:** 全部在 `packages/conatus_code` 子模块。A 新增 `BackgroundTaskService`（根上下文服务）+ 4 工具 + `/background` 命令；B 改 `ConatusTuiController.submit/_afterTurn/interrupt/_unbind`；C 重构 `CheckpointStore`（turn 0 全量 base + 差量），manager/命令面不变。

**Tech Stack:** Dart 3.10+、`ShellExecutor.start`（Local/沙箱均已实现）、`[background]` 既有配置。

**Spec:** `docs/superpowers/specs/2026-09-24-conatus-code-epoch3-design.md`

## Global Constraints

- AGENTS.md 硬约束：函数体 ≤40 行、class ≤150 行、单文件 ≤200 行（测试不限）、参数 ≤4（超限加 `// REASON:`）、if/else/switch ≤3（语句级）、嵌套 ≤2、禁嵌套三元、early return。
- 不跑 `dart format`；单引号；中文注释；包内相对导入。
- 子模块内提交（`feat(code): ...`）；父仓库 `chore(code): 同步子模块 gitlink（<简述>）`。
- 每个 Task 末尾 `dart analyze` + 相关测试通过后提交；三期末尾 `bash tool/build_binary.sh` 重建。
- 只 add 自己碰的文件（子模块有用户未提交的 UI 改动）；全量 7 个 UI 红测试为预期，不作回归。

## Review Focus

1. **后台任务超上限** → 拒绝并提示「已达后台任务上限（N）」；`max_running_tasks=0` 视为不限制（A-Task 1 钉）。
2. **后台命令被沙箱拒**（`RejectedShellProcess`）→ 工具失败映射「命令被沙箱拒绝」而非挂起（A-Task 2 钉）。
3. **队列满（20 条）** → 拒绝新输入并提示，不静默丢弃（B-Task 1 钉）。
4. **Esc 打断** → 取消当前轮 + 清空队列 + 明确提示条数（B-Task 2 钉）。
5. **会话切换** → 队列清空（B-Task 2 钉）。
6. **cron/提醒 busy 时投递** → 仍返回 false 由调度器重试，不入队（B-Task 1 钉）。
7. **delta 恢复合成**：base 铺底 + 差量覆盖/删除 + 删当前多余；被删文件补回、新增文件删除、改动文件覆盖（C-Task 2 钉）。
8. **旧检查点兼容**：无 `kind` 字段的 manifest 按 base 读（C-Task 1 钉）。

---

## A. 后台任务执行器

### Task A1：`BackgroundTaskService`

**Files:** New `lib/src/background/background_tasks.dart`；Test `test/background/background_tasks_test.dart`

- [x] `BackgroundTask`：`id` / `command` / `startedAt` / `ShellProcess` / 累计输出缓冲。
- [x] `BackgroundTaskService(shell, {maxRunningTasks = 4, maxRecords = 20})`：
  - `Future<String> start(String command, {String? cwd})` → `shell.resolve(ShellExecRequest(...))` + `shell.start(spec)`；`maxRunningTasks` 非正 = 不限；超限抛 `BackgroundException('limit', ...)`；任务 id `bg-<n>`。
  - 订阅 `process.done`：标记 completed；输出经 `readOutput()` 增量叠加进缓冲；被杀标记 killed。记录保留最近 `maxRecords` 条。
  - `List<BackgroundTaskView> list()`（id/command/status/exitCode/elapsed/输出字节数）。
  - `String output(String id)`（累计全量）；`bool kill(String id)`。
- [x] 测试（fake ShellProcess）：start 成功、id 递增；上限拒绝（含 0=不限）；done 后 completed；输出增量叠加；kill；记录保留截断。
- [x] `dart analyze` + 通过，提交 `feat(code): BackgroundTaskService（后台任务执行器）（A1）`。

### Task A2：工具 + 装配 + `/background` 命令

**Files:** New `lib/src/background/background_tools.dart`；Modify `tui_app.dart` / `bin/conatus_code.dart` / `tui_commands.dart` / `tui_controller.dart`；Test `test/background/background_tools_test.dart` + `test/tui/tui_background_command_test.dart`

- [x] 4 工具（risk：high/low/low/medium）：`run_command_background`（command 必填、cwd 可选，返回 `bg-<n>`）/ `list_background_tasks` / `background_output`（task_id，含状态+输出尾部）/ `background_kill`；`provideBackgroundTools(ctx)` 注册。
- [x] `tui_app.dart`：装配 `'backgroundTasks'` 服务（`BackgroundConfig` 传入）；bin 传 `config.background`。
- [x] `/background [list|output <id>|kill <id>]` 命令（controller，读 `'backgroundTasks'`）。
- [x] 测试：工具走服务（fake shell）；沙箱拒绝（RejectedShellProcess）映射失败；命令三条子命令；服务缺失提示。
- [x] `dart analyze` + 通过，提交 `feat(code): 后台任务工具与 /background 命令（A2）`。

## B. 消息队列

### Task B1：入队 + 收口出队

**Files:** Modify `tui_controller.dart`；Test `test/tui/tui_message_queue_test.dart`

- [x] 控制器字段 `_queue: List<(String, List<TuiAttachment>)>` + `kMessageQueueCap = 20`；`queuedCount` getter。
- [x] `submit()`：busy 且 `_agent != null` → 队列满拒绝；否则入队 + system 提示「已排队（第 N 条）」并 return（Review Focus #3）。
- [x] `_afterTurn` 末尾：队列非空且 !busy → `unawaited(submit(出队项))`（附件原样带）。
- [x] 测试：busy 入队、收口依次出队执行（scripted llm 断言轮次顺序）、满拒绝、cron/提醒 busy 仍返回 false 不入队（Review Focus #6）。
- [x] `dart analyze` + 通过，提交 `feat(code): 消息队列（busy 时排队追问）（B1）`。

### Task B2：打断清空 + 会话切换清空

**Files:** Modify `tui_controller.dart`；Test `test/tui/tui_message_queue_test.dart`（补例）

- [x] `interrupt()`：cancel 后若队列非空 → 清空 + 提示「已打断并清空 N 条排队消息」（Review Focus #4）。
- [x] `_unbind()`：清空队列（Review Focus #5）。
- [x] 测试：Esc 清空并提示；切会话队列空。
- [x] `dart analyze` + 通过，提交 `feat(code): 打断与切会话清空消息队列（B2）`。

## C. delta 快照优化

### Task C1：manifest 与快照 v2（base + delta）

**Files:** Modify `checkpoint_types.dart` / `checkpoint_store.dart`；Test `test/checkpoint/checkpoint_delta_test.dart`（新）+ 改写 `checkpoint_store_test.dart`

- [x] `CheckpointManifest` 扩：`kind`（base/delta）、base 的 `files` 改带 `{path, mtimeMs, size}` 的条目列表（`CheckpointFileEntry`）、delta 的 `changed` / `deleted`；`fromJson` 兼容无 kind 的旧格式（按 base，files 为路径列表）（Review Focus #8）。
- [x] `snapshot(sessionId, turn, {lastEventId})`：turn 0 全量 base（记 mtimeMs/size）；turn N 遍历工作区与 base stats 比对 → 复制 changed（含新增）、记 deleted；写对应 kind 的 manifest。
- [x] `CheckpointStore.list` → `List<CheckpointInfo>`（turn + 有效文件数：base=全量数，delta=base+changed−deleted）。
- [x] `prune`：保留 turn 0 + 最近 `keep-1` 个差量（`keep<=0` 不限）。
- [x] 测试：base 全量 + stats；turn 1 只存 changed/deleted；mtime+size 不变不改动；list 有效计数；prune 保 base + keep-1 差量；旧格式兼容读。
- [x] `dart analyze` + 通过，提交 `feat(code): checkpoint delta 快照（base + 差量）（C1）`。

### Task C2：两步恢复 + 全量回归

**Files:** Modify `checkpoint_store.dart`（restore）；Test `checkpoint_delta_test.dart` 补恢复

- [x] `restore(sessionId, turn)`：target 为 base → 铺底 + 删多余；为 delta → base 铺底 + 差量覆盖（changed）+ 删除（deleted）+ 删当前多余（Review Focus #7）。
- [x] 全量 checkpoint/rewind 测试回归（manager/命令测试断言不变或仅数量语义更新）。
- [x] `dart analyze` + 全量受影响测试通过 + `bash tool/build_binary.sh`，提交 `feat(code): delta 快照两步恢复（C2）`。

## 收尾

- 三期全绿后父仓库 gitlink + push；`docs/superpowers` 归档（spec 状态、plan 勾选、缺口 spec #4/#15 与 checkpoint 边界标记）。
