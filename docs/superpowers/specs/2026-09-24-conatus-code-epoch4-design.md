# nava 四期：/commit + /doctor + Hooks + delta 哈希检测 — 设计

日期：2026-09-24
状态：已实施（2026-09-24，见实现计划）
范围：`packages/conatus_code` 子模块（Hooks 触碰 `conatus_foundation` 的 `ToolRegistry` 中间件链）

## 背景

三期之后按重要性排的下一批：`/commit`（日常提交闭环）、`/doctor`（诊断）、
Hooks（扩展性）、delta 哈希检测（正确性收口）。

## A. `/commit`（spec #13）

### 决策记录

| 决策点 | 结论 | 理由 |
|--------|------|------|
| 工具形态 | 新增 `git_commit` 工具（high 风险 → 审批） | 模型经审批提交，权限语义与 run_command 一致 |
| 命令形态 | `/commit` 提交一段固定工作流提示词，由模型驱动（git_diff --staged → 写 Conventional Commits → git_commit） | 复用 Agent Loop，模型可见完整 diff 与决策链 |
| 消息参数 | `message`（必填）+ `body`（可选），经 `-m` 传参 + shell 单引号转义 | 复用 GitDiffTool._quote 形态 |
| 空暂存 | 由模型经 git_diff --staged 发现并提示用户，/commit 不预判 | 交给模型上下文，避免控制器重复取 diff |
| 沙箱/审批 | git_commit 走 `'shell'` 缝（沙箱 + CommandPolicy）；high 风险走审批链 | 提交是持久副作用 |

## B. `/doctor`（spec #16）

### 决策记录

| 决策点 | 结论 | 理由 |
|--------|------|------|
| 检查项 | 沙箱后端（probe）、`rg` 可用性、provider 连通（registry 有配置）、凭据脱敏、配置路径、MCP server 数 | 全在既有装配里，只聚合展示 |
| 输出 | 逐项 ✓/✗ + 修复提示；整体通过/有告警 | 一眼定位 |
| 副作用 | 只读检查，不修 | v1 诊断先行 |
| 触发 | `/doctor` 命令（不经模型） | 用户自查 |

## C. Hooks（spec #14）

### 决策记录

| 决策点 | 结论 | 理由 |
|--------|------|------|
| 事件 | `PreToolUse`（工具执行前，可拒绝/改写）/ `PostToolUse`（工具返回后）/ `Stop`（轮次收口） | 对齐 Claude Code 三事件 |
| 配置 | config.toml `[hooks.<事件>] = ["命令"]`（多条顺序执行） | 文本配置即插即用 |
| 执行 | dart:io 直连起进程（不经过 `'shell'` 缝，避免递归沙箱裁决 hook 命令） | hook 是用户本机命令，非模型产物 |
| 挂点 | `ToolRegistry` 中间件（Pre/Post）+ 控制器 `_afterTurn`（Stop） | Pre/Post 复用工具管线；Stop 复用轮次收口 |
| 失败语义 | hook 非零退出：Pre 拒绝工具、Post/Stop 只提示 | 护栏不能静默 |
| 环境变量 | hook 进程注入 `NAVA_HOOK_<事件>` + 工具名/参数 JSON | 可编程 |

## D. delta 哈希检测（checkpoint 已知边界）

### 决策记录

| 决策点 | 结论 | 理由 |
|--------|------|------|
| 检测 | base 条目增 `hash` 字段：mtime+size 不同即变；**相同则读文件算 SHA-256，与 base 比对**，不同也视为变 | 修「内容变但 mtime+size 不变」漏检 |
| 成本 | 仅 mtime+size 相同才读文件哈希（罕见），常规路径无额外 IO | 性能无损 |
| 兼容 | base manifest 增可选 `hash`；旧条目无 hash → 直接按不同处理一次（保守） | 升级安全 |
| 改动面 | `checkpoint_types`（条目加 hash）+ `checkpoint_store._snapshotDelta` | 内部 |

## 文件结构

| 文件 | 职责 |
|------|------|
| `lib/src/tools/git_tools.dart` | 加 `GitCommitTool`（复用 runGit） |
| `lib/src/tools/code_tools.dart` | 注册 `GitCommitTool` |
| `lib/src/tui/tui_controller.dart` | `/commit`、`/doctor`、Stop hook 挂点 |
| `lib/src/tui/tui_commands.dart` | 两条命令表项 |
| `lib/src/diagnose/doctor.dart` | **新**：`doctorChecks(app)` → 各项检查结果 |
| `lib/src/hooks/hooks.dart` | **新**：hook 配置读取 + 执行器 |
| `lib/src/config/config_schema.dart` / `config_parser.dart` / `config_loader.dart` | `[hooks]` 表 |
| `lib/src/checkpoint/checkpoint_types.dart` / `checkpoint_store.dart` | 条目 hash + delta 哈希比对 |
| 测试 | `test/tools/git_commit_test.dart`、`test/tui/tui_doctor_test.dart`、`test/hooks/`、`test/checkpoint/checkpoint_hash_test.dart` |

## 测试策略

- git_commit：成功/失败映射、消息转义、沙箱拒绝。
- doctor：各项 ✓/✗ 与提示（fake probe / 缺 provider）。
- hooks：Pre 拒绝工具、Post 触发、Stop 触发、非零退出语义、环境变量注入。
- delta 哈希：mtime+size 相同但内容变 → 差量包含；旧条目无 hash → 保守处理。
