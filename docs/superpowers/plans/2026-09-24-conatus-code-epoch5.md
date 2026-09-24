# nava 五期（! shell / /review / lint-on-edit）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 五期三件事：A `!` 快捷 shell 模式、B `/review` 审查命令、C lint-on-edit（模型改完自动跑 linter 并闭环）。

**Architecture:** 全部在 `packages/conatus_code` 子模块。A 改 `ConatusTuiController.handleLine`（`!` 前缀分支，走 `'shell'` 缝）；B 加 `/review` 提示词命令；C 新增 `LinterService`（探测/去抖/中间件）+ `[lint]` 配置。

**Tech Stack:** Dart 3.10+、`ShellExecutor` 缝、`ToolRegistry.use` 中间件、`[lint]` 配置表。

**Spec:** `docs/superpowers/specs/2026-09-24-conatus-code-epoch5-design.md`

## Global Constraints

- AGENTS.md 硬约束：函数体 ≤40 行、class ≤150 行、单文件 ≤200 行（测试不限）、参数 ≤4（超限加 `// REASON:`）、if/else/switch ≤3（语句级）、嵌套 ≤2、early return。
- 不跑 `dart format`；单引号；中文注释；包内相对导入。
- 子模块内提交（`feat(code): ...`）；父仓库 `chore(code): 同步子模块 gitlink（<简述>）`。
- 每 Task 末尾 `dart analyze` + 相关测试通过后提交；五期末尾 `bash tool/build_binary.sh` 重建。
- 只 add 自己碰的文件；7 个 UI 红测试为预期。

## Review Focus

1. **busy 时 `!` 命令** → 拒绝并提示（A 钉）。
2. **`!` 命令被沙箱拒**（`&&` 等形状）→ 失败映射含原因（A 钉）。
3. **`!` 空输入 / 只有 `!`** → 用法提示；`!!` 无历史 → 提示（A 钉）。
4. **`/review` 无未提交改动** → 模型经 git_diff 发现并说明（B 钉）。
5. **lint 探测不到 linter** → 静默跳过（C 钉）；**`[lint] command` 覆盖**生效（C 钉）。
6. **去抖**：10s 内多次编辑只跑一次 lint（C 钉）。

---

## A. `!` shell 模式

### Task A：`handleLine` 分支 + `_runShellBang`

**Files:** Modify `tui_controller.dart`；Test `test/tui/tui_shell_bang_test.dart`

- [x] `handleLine`：空行检查后、`/` 分支前，`line.startsWith('!')` → `await _runShellBang(line)` 并 return。
- [x] `_runShellBang`：`!` 空 → 用法提示；`!!` → 重跑 `_lastBangCommand`（无历史提示）；否则取 `!` 后内容存 `_lastBangCommand`。
- [x] 执行：`'shell'` 缝 `resolve(ShellExecRequest(command, timeoutMs: 60000))` + `run`；busy 拒绝（Review Focus #1）；成功显示 stdout（空则「（无输出）」）、失败合并 stderr+退出码（#2）。
- [x] 测试：`!echo hi` 上屏；`!!` 重跑；busy 拒绝；`!` 空用法；沙箱拒绝（fake shell 非零）映射失败。
- [x] `dart analyze` + 通过，提交 `feat(code): ! 快捷 shell 模式（五期 A）`。

## B. `/review`

### Task B：命令 + 提示词

**Files:** Modify `tui_commands.dart` / `tui_controller.dart`；Test `test/tui/tui_review_test.dart`

- [x] `/review`：提交提示词「审查当前未提交改动（git diff 未暂存+暂存）：命名、边界条件、安全隐患、性能问题；输出结构化发现清单，只审不改」。
- [x] 命令表加 `/review`。
- [x] 测试：/review 触发一轮且提示词含「审查」与「git diff」；命令表含 review。
- [x] `dart analyze` + 通过，提交 `feat(code): /review 审查命令（五期 B）`。

## C. lint-on-edit

### Task C1：`[lint]` 配置

**Files:** Modify `config_schema.dart` / `config_parser.dart` / `config_loader.dart`；Test `test/config/config_lint_test.dart`

- [x] `LintConfig`（`enabled=true` / `command` 可空 / `debounceSeconds=10`）+ `ConatusCodeConfig.lint`。
- [x] `_readLint()`；模板加 `[lint]` 注释示例。
- [x] 测试：缺省、完整、`debounce_seconds` 非法抛错。
- [x] `dart analyze` + 通过，提交 `feat(code): config 解析 [lint] 表（五期 C1）`。

### Task C2：`LinterService` + 中间件 + 装配

**Files:** New `lib/src/lint/linter.dart`；Modify `tui_app.dart` / `bin/conatus_code.dart`；Test `test/lint/linter_test.dart`

- [x] `LinterService(shell, {config, workdir})`：
  - 惰性探测命令：`dart analyze`（pubspec.yaml）/ `eslint .`（package.json + eslint 配置）/ `go vet ./...`（go.mod）/ `cargo check`（Cargo.toml）/ `[lint] command` 覆盖（Review Focus #5）。
  - `Future<String?> runIfDue(now)`：去抖（`debounceSeconds`，首跑立即）；超时 30s；输出截断 2000 字符；无 linter → null。
- [x] 中间件：`mount(ToolRegistry)` 包 next；`call.name` 属于 `{write_file, edit_file, apply_patch}` 且结果非错误 → `runIfDue` → 告警追加进 content（Review Focus #6）。
- [x] `tui_app`：装配 `'linter'` 服务（`[lint]` 配置 + workdir）；bin 传 `config.lint`。
- [x] 测试（fake shell 脚本化 `dart analyze` 输出）：探测映射；编辑工具后追加告警；10s 内二次编辑不连跑（注入时钟或手动调 runIfDue）；`enabled=false` 不触发；command 覆盖。
- [x] `dart analyze` + 通过 + `bash tool/build_binary.sh`，提交 `feat(code): lint-on-edit（模型改完自动自检）（五期 C2）`。

## 收尾

- 五期全绿后父仓库 gitlink + push；`docs/superpowers` 归档（spec 状态、plan 勾选）。
