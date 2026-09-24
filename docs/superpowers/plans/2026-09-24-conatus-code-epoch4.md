# nava 四期（/commit / /doctor / Hooks / delta 哈希）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 四期四件事：A `git_commit` 工具 + `/commit` 工作流、B `/doctor` 诊断、C Hooks（Pre/Post/Stop）、D delta 哈希检测。

**Architecture:** 全部在 `packages/conatus_code` 子模块。A 加 `GitCommitTool`（复用 runGit）+ `/commit` 提示词；B 加 `doctorChecks` 聚合既有装配信息；C 加 `[hooks]` 配置 + 执行器，Pre/Post 挂 `ToolRegistry` 中间件、Stop 挂 `_afterTurn`；D checkpoint 条目加 hash。

**Tech Stack:** Dart 3.10+、`runGit`、`ToolRegistry` 中间件、`[hooks]` 配置表。

**Spec:** `docs/superpowers/specs/2026-09-24-conatus-code-epoch4-design.md`

## Global Constraints

- AGENTS.md 硬约束：函数体 ≤40 行、class ≤150 行、单文件 ≤200 行（测试不限）、参数 ≤4（超限加 `// REASON:`）、if/else/switch ≤3（语句级）、嵌套 ≤2、early return。
- 不跑 `dart format`；单引号；中文注释；包内相对导入。
- 子模块内提交（`feat(code): ...`）；父仓库 `chore(code): 同步子模块 gitlink（<简述>）`。
- 每 Task 末尾 `dart analyze` + 相关测试通过后提交；四期末尾 `bash tool/build_binary.sh` 重建。
- 只 add 自己碰的文件（子模块有用户未提交的 UI 改动）；7 个 UI 红测试为预期。

## Review Focus

1. **/commit 无 staged 改动** → 模型经 git_diff --staged 发现并提示，不报错（A2 钉）。
2. **git_commit 沙箱拒绝 / 非零退出** → 失败映射含 stderr（A1 钉）。
3. **/doctor 沙箱后端不可用** → 该项 ✗ 并提示 `[sandbox] enabled=false` 选项，不崩（B 钉）。
4. **Pre hook 非零退出** → 拒绝该工具并给原因；Post/Stop 失败只提示（C1/C2 钉）。
5. **hook 命令不存在** → 按失败处理（Pre 拒绝、Post/Stop 提示），不抛（C1 钉）。
6. **delta 哈希：mtime+size 相同但内容变** → 差量包含该文件；旧条目无 hash → 保守按不同（D 钉）。

---

## A. `/commit`

### Task A1：`GitCommitTool`

**Files:** Modify `git_tools.dart` / `code_tools.dart`；Test `test/tools/git_commit_test.dart`

- [x] `GitCommitTool(shell, timeout)`：name `git_commit`、risk **high**；params `message`（必填）、`body`（可选）。
- [x] 命令：`git --no-pager commit -m <msg> [-m <body>]`，消息经单引号转义（复用 `_quote`）；超时/非零 → 失败映射（含 stderr，Review Focus #2）。
- [x] `provideCodeTools` 注册（有 shell 时）。
- [x] 测试（fake shell）：成功返回 commit 输出、消息含空格/引号转义、body 拼接、非零退出失败。
- [x] `dart analyze` + 通过，提交 `feat(code): GitCommitTool（/commit 前置）（四期 A1）`。

### Task A2：`/commit` 命令

**Files:** Modify `tui_controller.dart` / `tui_commands.dart`；Test `test/tui/tui_commit_command_test.dart`

- [x] `/commit`：提交固定提示词「执行提交流程：git_diff --staged 查看暂存差异 → 写 Conventional Commits 提交信息（scope + 中文）→ 用 git_commit 提交；无暂存改动时提示用户」。
- [x] 命令表加 `/commit`。
- [x] 测试（scripted llm）：/commit 触发一轮且提示词含 git_commit。
- [x] `dart analyze` + 通过，提交 `feat(code): /commit 提交流程命令（四期 A2）`。

## B. `/doctor`

### Task B1：`doctorChecks` + `/doctor` 命令

**Files:** New `lib/src/diagnose/doctor.dart`；Modify `tui_controller.dart` / `tui_commands.dart`；Test `test/tui/tui_doctor_test.dart`

- [x] `doctorChecks(app)` → `List<DoctorCheck>`（name / ok / hint）：沙箱后端（`'sandboxBackend'` 或 probe 结果缓存）、rg 可用性（shell `which rg` 或 'rg' 服务）、provider（registry 有 profile）、凭据（configPath 存在）、MCP（`'mcp'` 服务 server 数）。
- [x] `/doctor`：逐项 ✓/✗ 输出 + 修复提示（Review Focus #3）。
- [x] 测试：各项 ok/fail 路径、缺 provider 提示、后端不可用提示。
- [x] `dart analyze` + 通过，提交 `feat(code): /doctor 诊断命令（四期 B）`。

## C. Hooks

### Task C1：`[hooks]` 配置 + 执行器 + Pre/Post 挂点

**Files:** New `lib/src/hooks/hooks.dart`；Modify `config_schema.dart` / `config_parser.dart` / `config_loader.dart` / `tui_app.dart`；Test `test/config/config_hooks_test.dart` + `test/hooks/hooks_test.dart`

- [x] `[hooks]` 表：`pre_tool_use` / `post_tool_use` / `stop` 各为字符串数组（命令）。
- [x] `runHooks(commands, env)` → 逐条 dart:io 起进程（不经过 `'shell'` 缝），聚合退出码与输出。
- [x] 装配：`provideHooks(ctx, config.hooks)` 注册 `'hooks'` 服务；`Hooks.middleware()` 挂 `ToolRegistry`（Pre 非零 → 拒绝工具 + 原因；Post 失败只提示）；`Hooks.onStop()` 供 `_afterTurn` 调。
- [x] 环境变量：`NAVA_HOOK_EVENT` / `NAVA_HOOK_TOOL` / `NAVA_HOOK_ARGS_JSON`。
- [x] 测试（fake：hook 命令用 dart:io 跑真实 shell 脚本或注入命令替换）：
  - Pre 非零拒绝工具；Post 触发；命令不存在按失败（Review Focus #4/#5）。
  - 注意测试内 hook 命令用 `true`/`false`/`echo` 即可（dart:io 直连）。
- [x] `dart analyze` + 通过，提交 `feat(code): Hooks 配置与 Pre/Post 挂点（四期 C1）`。

### Task C2：Stop hook 挂 `_afterTurn`

**Files:** Modify `tui_controller.dart`；Test `test/tui/tui_stop_hook_test.dart`

- [x] `_afterTurn` 末尾调 `'hooks'` 服务的 `onStop()`（失败只提示）。
- [x] 测试：Stop hook 在轮次收口触发（真实 `echo` 写临时文件断言）。
- [x] `dart analyze` + 通过，提交 `feat(code): Stop hook 挂轮次收口（四期 C2）`。

## D. delta 哈希检测

### Task D1：条目 hash + 差量哈希比对

**Files:** Modify `checkpoint_types.dart` / `checkpoint_store.dart`；Test `test/checkpoint/checkpoint_hash_test.dart`

- [x] `CheckpointFileEntry` 加 `hash`（String?）；base 快照记 SHA-256；`fromJson` 兼容旧条目（hash 缺省 null）。
- [x] `_snapshotDelta`：mtime+size 相同 → 读当前文件哈希与 base 比对，不同也算 changed（Review Focus #6）；旧条目无 hash → 直接按不同。
- [x] 测试：内容变但 mtime+size 被手动还原 → 差量包含；旧清单（无 hash）→ 保守全变。
- [x] `dart analyze` + 全量 checkpoint 回归 + `bash tool/build_binary.sh`，提交 `feat(code): delta 哈希级变化检测（四期 D）`。

## 收尾

- 四期全绿后父仓库 gitlink + push；`docs/superpowers` 归档（spec 状态、plan 勾选、缺口 spec #13/#14/#16 与 checkpoint 边界标记）。
