# conatus_code 功能缺口补齐 Implementation Plan

> **Status: 一期（M1–M5）已实施完毕，56 项任务全部勾选。** 后续项（checkpoint/rewind、
> 后台任务、hooks 等）见 spec「后续另立计划」表，各自出计划后再开新轮次。
>
> **二期（2026-09-24）：checkpoint/rewind（spec #3）已实施完毕**
> （`docs/superpowers/plans/2026-09-24-conatus-code-checkpoint-rewind.md`，19 项全勾）。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按 spec 优先级补齐 nava 的五批功能：M1 MCP 接入、M2 Headless 非交互模式、M3 项目上下文文件（AGENTS.md）加载 + `/init`、M4 小命令批（`/compact` / `/cost` / `--version` / `--continue`）、M5 意图路由 README 失真修正。

**Architecture:** 全部改动在 `packages/conatus_code` 子模块。M1 在 config 层新增 `[mcp.servers.*]` 解析，装配期经 `conatus_mcp` 的 `provideMcp` / `McpRegistry.attach` 逐台挂载（单台失败不阻塞启动）；M2 给 `ConatusTuiRuntime.create` 加 `interactive` 开关剥离 TUI 专属装配，bin 增加 headless 分支；M3 启动时读 workdir 内 AGENTS.md/NAVA.md 注入 SystemPrompt 项目段；M4 复用已装配的 `'compaction'` / `'costTracker'` 服务与 `SessionStore.persistedIds`，只加命令面与 CLI 解析；M5 纯文档。

**Tech Stack:** Dart 3.10+、`conatus_mcp`（`McpServerConfig` / `provideMcp` / `McpRegistry`）、`conatus_compaction`（`CompactionEngine.compactIfNeeded`）、`conatus_agent`（`summarizeEvents`）、`toml` 0.18、`dart compile exe -D`。

**Spec:** `docs/superpowers/specs/2026-09-24-conatus-code-feature-gaps-design.md`

## Global Constraints

- 仓库 AGENTS.md 硬约束：函数体 ≤40 行、class ≤150 行、单文件 ≤200 行（测试文件不受限）、函数参数 ≤4（超限必须加 `// REASON:`）、每函数 if/else/switch ≤3、嵌套 ≤2、连续 `&&/||` ≤2、禁嵌套三元、优先 early return。
- 布尔命名禁 `is/has/can/should` 前缀；函数名「动词 + 名词」；包内相对导入；单引号；中文文档注释。
- 仓库未强制 `dart format`——不要跑它；风格对齐周围代码。
- `packages/conatus_code` 是独立 git 子模块：**实现与提交都在子模块内**（`feat(code): ...` / `fix(code): ...`），根仓库只提交 gitlink（`chore(code): 同步子模块 gitlink（<简述>）`）。
- 每个 Task 末尾：子模块内 `dart analyze` + `dart test` 通过后提交一次。
- 每个 Milestone 末尾追加：`bash tool/build_binary.sh` 重建 `dist/nava`（AGENTS.md 硬要求：只改源码不重建视为未完成），再提交父仓库 gitlink。
- 凭据脱敏硬约束：MCP 的 `env` / `headers` 经 `resolveCredentialPlaceholders` 解析后**不得写进日志/事件/会话记录**；Dart 源码里写 `r'...'` 原始字符串或转义 `\$`。
- 面向用户文案一律中文。

## Review Focus

以下失败模式 spec 未逐条列测试，但用户会撞上；每条在对应 Task 里钉住：

1. **MCP server 连接失败**（`npx` 不在 PATH、url 不可达）→ 启动不崩，stderr 提示「server <名> 连接失败，已跳过」，其余 server 照常（M1-Task 2 钉）。
2. **`${KEY}` 占位符无对应凭据** → 原样保留、不报错、不写日志（`resolveCredentialPlaceholders` 既有语义）；连接失败按第 1 条处理（M1-Task 2 钉）。
3. **headless 下模型调 `ask_user`** → `interactive: false` 时不注册该工具，模型收到 tool-not-found 而非挂起（M2-Task 2 钉）。
4. **headless + 沙箱后端不可用** → fail-closed 语义不变（命令执行禁用），进程不崩、正常产出 reply（M2-Task 3 钉）。
5. **`/compact` 历史太短** → `compactIfNeeded` 返回 `null`，提示「历史太短，无需压缩」而非报错（M4-Task 1 钉）。
6. **`--continue` 无历史会话** → 新建会话并 stderr 提示，不报错退出（M4-Task 4 钉）。
7. **AGENTS.md 不存在 / 超大** → 不存在静默跳过；超过 16 KB 截断并在段尾标注（M3-Task 1 钉）。
8. **`--version` 在 `dart run`（未编译）下** → 输出 `dev`（M4-Task 3 钉）。

---

## M1：MCP 接入（spec #1）

**目标：** config.toml `[mcp.servers.<name>]` 声明 MCP server，启动时经 `conatus_mcp` 挂载，工具进 `ToolRegistry`（`server__tool` 前缀），风险映射走既有审批链；`/mcp` 查看已挂 server。

**决策记录：**

| 决策点 | 结论 | 理由 |
|--------|------|------|
| 配置位置 | config.toml `[mcp.servers.*]`，与 providers 同文件 | 单一配置来源，与 provider 收敛决策一致 |
| 失败语义 | 逐台 try/catch，单台失败提示并跳过 | 一台配错不应拖垮整个启动 |
| stdio 子进程与沙箱 | **不走** Layer 2 沙箱：MCP server 是用户显式配置的受信端 | 与 Claude Code / Codex 同姿态；沙箱管的是模型写的命令 |
| schema 类型 | config 层自定义 `McpServerSpec`，装配时映射为 `conatus_mcp` 的 `McpServerConfig` | config 包不依赖 mcp 包，分层干净 |
| `/mcp` 命令 | 只读 list（server 名 + 工具数 + 传输类型） | 重连/增删留给后续，不在本期 |

### 文件结构（M1）

| 文件 | 职责 |
|------|------|
| `lib/src/config/config_schema.dart` | 新增 `McpServerSpec` / `McpConfig`；`ConatusCodeConfig` 加 `mcp` |
| `lib/src/config/config_parser.dart` | `_readMcp()`：解析 `[mcp.servers.*]`（type/command/args/env/url/headers） |
| `lib/src/config/config_writer.dart` | 首启模板补 `[mcp.servers.*]` 注释示例 |
| `lib/src/mcp/mcp_assembly.dart` | **新文件**：`attachMcpServers(app, specs, credentials)` 逐台挂载、失败跳过 |
| `lib/src/tui/tui_app.dart` | `create` 加 `mcpServers` 形参，凭据装配后调 `attachMcpServers` |
| `bin/conatus_code.dart` | 传 `config.mcp.servers` |
| `lib/src/tui/tui_commands.dart` + `tui_controller.dart` | `/mcp` 只读列表 |
| `test/config/config_mcp_test.dart` | 解析测试 |
| `test/mcp/mcp_assembly_test.dart` | 装配测试（fake transport） |
| `README.md` / `CHANGELOG.md` | 配置示例与变更记录 |

### Task 1：config schema + parser（`[mcp.servers.*]`）

**Files:** Modify `config_schema.dart` / `config_parser.dart` / `config_writer.dart`；Test `test/config/config_mcp_test.dart`

- [x] `McpServerSpec`：`name` / `type`（`stdio` / `http` / `sse` 字符串）/ `command?` / `args` / `env` / `url?` / `headers`；`McpConfig.servers` 列表；`ConatusCodeConfig` 加 `mcp`（缺省空）。
- [x] `_readMcp()`：`readTable('mcp')` → `servers` 子表逐条解析；`type` 未知值抛 `ConfigException`；`stdio` 缺 `command`、`http`/`sse` 缺 `url` 抛 `ConfigException`（与 `McpServerConfig` 构造期校验同语义，提前到解析期）。
- [x] `env` / `headers` 值原样保留 `${KEY}` 文本（**解析期不替换**，替换在装配期经 Credentials）。
- [x] `config_writer` 模板加注释掉的示例段。
- [x] 测试：stdio/http/sse 三种合法解析；缺 command/url 报错；未知 type 报错；`env` 内联表解析；`${KEY}` 原样保留。
- [x] `dart analyze` + `dart test` 通过，子模块提交 `feat(code): config 解析 [mcp.servers.*]`。

### Task 2：装配（逐台挂载、失败跳过）

**Files:** New `lib/src/mcp/mcp_assembly.dart`；Modify `tui_app.dart` / `bin/conatus_code.dart`；Test `test/mcp/mcp_assembly_test.dart`

- [x] `attachMcpServers(Context app, List<McpServerSpec> specs, Credentials credentials)`：空列表直接返回；首台前先 `provideMcp(app, const [])` 建 registry（拿 `'mcp'` 服务键），随后逐台 `registry.attach(ctx, McpClient(transport: ..., serverName: ...))`——传输按 spec.type 分派（`StdioTransport` / `HttpTransport` / `SseTransport`），`env`/`headers` 先过 `resolveCredentialPlaceholders`。
- [x] 单台 attach 抛错 → `stderr` 提示「MCP server <名> 连接失败，已跳过：<message>」，继续下一台（Review Focus #1/#2）。
- [x] `ConatusTuiRuntime.create` 加 `List<McpServerSpec>? mcpServers` 形参，在凭据装配之后、返回之前调用；bin 传 `config.mcp.servers`。
- [x] 测试：fake `McpTransport`（脚本化握手 + tools/list）挂两台，一台 attach 抛错 → registry 只有一台、stderr 有提示；`${KEY}` 经注入的 Credentials 解析。
- [x] `dart analyze` + `dart test` 通过，子模块提交 `feat(code): 装配 MCP server（逐台挂载、失败跳过）`。

### Task 3：`/mcp` 命令 + 文档

**Files:** Modify `tui_commands.dart` / `tui_controller.dart` / `README.md` / `CHANGELOG.md`；Test `test/tui/tui_mcp_command_test.dart`

- [x] `/mcp`：读 `'mcp'` 服务的 `McpRegistry`，列出每台 server（名 / 传输类型 / 已接入工具数）；无 server 时提示「未配置 MCP server（config.toml `[mcp.servers.*]`）」。
- [x] README「配置」节加 `[mcp.servers.*]` 示例与 `${KEY}` 占位符说明（强调 stdio 不走沙箱的受信前提）；CHANGELOG 记录。
- [x] 测试：装配两台 fake server 后 `/mcp` 输出包含两者。
- [x] `dart analyze` + `dart test` + `bash tool/build_binary.sh`，子模块提交 `feat(code): /mcp 命令与 MCP 文档`，父仓库提交 gitlink。

---

## M2：Headless 非交互模式（spec #7）

**目标：** `nava -p "<任务>"` 单轮跑完打印 reply 即退出，支持 `--output-format text|json` 与 `--session` 恢复；CI/脚本可用。

**决策记录：**

| 决策点 | 结论 | 理由 |
|--------|------|------|
| 入口形态 | 同一 bin 内分支，不新增入口文件 | 装配复用最大化 |
| 审批 | headless 不挂审批中间件（`interactive: false` 时不提供 `'approval'` 服务、不注册 `AskUserTool`） | 无人值守不能卡在提问上；沙箱仍是安全底线 |
| 沙箱 | 照常（两层全开，fail-closed 语义不变） | headless 恰恰是最需要沙箱的场景 |
| 输出 | `text`（缺省）只打印 reply；`json` 打印 `{reply, sessionId, steps}` 单行 JSON | 脚本消费 |
| 退出码 | 成功 0；模型/工具轮次失败 1；配置错误 2（沿用现有 ConfigException 分支的语义扩展） | 脚本可判 |
| prompt 传入 | `-p` / `--print <文本>`（值缺失视为未指定，不报错） | 与 TuiOptions 宽松解析风格一致 |

### 文件结构（M2）

| 文件 | 职责 |
|------|------|
| `lib/src/tui/tui_options.dart` | 加 `print` / `outputFormat` 字段与解析 |
| `lib/src/tui/tui_app.dart` | `create` 加 `interactive`（缺省 true）；false 时跳过 tuiChoice / AskUserTool / approval 服务 |
| `lib/src/headless/headless_runner.dart` | **新文件**：`runHeadless(runtime, prompt, ...)` 建会话、跑一轮、格式化输出 |
| `bin/conatus_code.dart` | headless 分支：`options.print != null` 时不进 TUI |
| `test/tui/tui_options_print_test.dart` | 解析测试 |
| `test/headless/headless_runner_test.dart` | 端到端（fake LLM provider） |

### Task 1：CLI 解析（`-p` / `--output-format`）

**Files:** Modify `tui_options.dart`；Test `test/tui/tui_options_print_test.dart`

- [x] `TuiOptions` 加 `print`（`String?`）与 `outputFormat`（`String`，缺省 `text`，只接受 `text`/`json`，其他值按 `text`）。
- [x] `-p` / `--print` 后无值或下一参数以 `-` 开头 → 视为未指定（与 `--session` 同风格）。
- [x] usage 文案补两行。
- [x] 测试：`-p` 正常取值、缺值、`--output-format json`、非法 format 回落 text。
- [x] `dart analyze` + `dart test` 通过，子模块提交 `feat(code): CLI 解析 -p/--print 与 --output-format`。

### Task 2：`create` 的 `interactive` 开关

**Files:** Modify `tui_app.dart`；Test `test/tui/tui_runtime_assembly_test.dart`（补例）

- [x] `create` 加 `bool interactive = true`；false 时跳过：`TuiChoicePrompt` 提供、`provideApproval`、`AskUserTool` 注册（Review Focus #3）。
- [x] 其余装配（工具/沙箱/搜索/技能/MCP/压缩/记忆/cron）不变。
- [x] 测试：`interactive: false` 时 `app.get('approval') == null`、`tools.names` 不含 `ask_user`。
- [x] `dart analyze` + `dart test` 通过，子模块提交 `feat(code): 运行时装配加 interactive 开关`。

### Task 3：headless 分支与输出

**Files:** New `lib/src/headless/headless_runner.dart`；Modify `bin/conatus_code.dart`；Test `test/headless/headless_runner_test.dart`

- [x] `runHeadless`：`sessions.create()`（或 `--session` 指定时 `open`）→ 会话子上下文 `provideAgentLoop`（复用 `ConatusTuiController._bind` 的插件清单中 TUI 无关部分：plan/goal/schedule 不装，只装 Agent Loop 必需）→ `agent.run(prompt)` → 按 format 输出 → `sessions.flush()` + `runtime.dispose()`。
- [x] `AgentCancelled`/`LlmException`/其他异常 → stderr 中文提示 + 退出码 1；`ConfigException` 维持退出码 1 现状还是改 2——**改为 2**（决策表），bin 里 `exit(2)`。
- [x] 沙箱后端不可用时 stderr 提示照常、流程继续（Review Focus #4）。
- [x] 测试：fake `LlmProvider`（注册进 providers 或直传 `llm:`）跑通 text/json 两种输出；json 含 `reply`/`sessionId` 字段。
- [x] `dart analyze` + `dart test` + `bash tool/build_binary.sh`，子模块提交 `feat(code): headless 非交互模式（nava -p）`，父仓库提交 gitlink。

---

## M3：AGENTS.md 加载 + `/init`（spec #8）

**目标：** 启动时把 workdir 的 `AGENTS.md` / `NAVA.md` 注入 system prompt 项目段；`/init` 让模型扫描仓库生成 AGENTS.md。

**决策记录：**

| 决策点 | 结论 | 理由 |
|--------|------|------|
| 查找范围 v1 | **只读 workdir 根**的 `AGENTS.md` 与 `NAVA.md`（不向上递归） | 向上递归会越出 Layer 1 fs jail 的沙箱根，被 jail 挡；v1 保持简单 |
| 两文件并存 | 都读，AGENTS.md 在前，NAVA.md 在后拼接 | NAVA.md 作为项目自定义补充 |
| 大小上限 | 单文件超 16 KB 截断 + 段尾标注「（已截断）」 | 防超大文件吃掉上下文（Review Focus #7） |
| 读取通道 | 直接用 `dart:io`（启动期、jail 装配前），不走 `'fs'` 服务 | 避免 jail 语义干扰；只读 |
| `/init` 实现 | 不直接写文件：submit 固定提示词让模型生成（经 write_file + 审批落盘） | 复用既有管线，无新副作用面 |

### 文件结构（M3）

| 文件 | 职责 |
|------|------|
| `lib/src/tui/project_context.dart` | **新文件**：`loadProjectContext(workdir)` 读 AGENTS.md/NAVA.md，截断拼接 |
| `lib/src/tui/tui_app.dart` | `create` 加 `workdir` 形参；有内容时 `prompt.section(PromptSection(name: 'project', ...))` |
| `bin/conatus_code.dart` | 传 workdir |
| `lib/src/tui/tui_commands.dart` + `tui_controller.dart` | `/init` 命令 |
| `test/tui/project_context_test.dart` | 加载/截断/缺失测试 |

### Task 1：`loadProjectContext` + SystemPrompt 注入

**Files:** New `lib/src/tui/project_context.dart`；Modify `tui_app.dart` / `bin/conatus_code.dart`；Test `test/tui/project_context_test.dart`

- [x] `Future<String?> loadProjectContext(String workdir)`：依次试读 `<workdir>/AGENTS.md`、`<workdir>/NAVA.md`；都不存在返回 `null`；单文件超 16 KB 截断并标注；两段非空时拼 `AGENTS.md` 内容 + `\n\n` + NAVA.md 内容。
- [x] `create` 加 `String? workdir`；非空时调用并在有结果时注册 `PromptSection(name: 'project', text: () => content)`（persona/coding 段之后）。
- [x] 测试：两文件都没有 → null；只有 AGENTS.md；并存拼接；超限截断标注。
- [x] `dart analyze` + `dart test` 通过，子模块提交 `feat(code): 启动加载 AGENTS.md/NAVA.md 进 system prompt`。

### Task 2：`/init` 命令

**Files:** Modify `tui_commands.dart` / `tui_controller.dart`；Test `test/tui/tui_init_command_test.dart`

- [x] `/init`：`submit` 固定提示词（「扫描当前仓库结构与关键文件，生成 AGENTS.md：项目概述、构建/测试命令、代码风格、边界注意事项，经 write_file 写入仓库根」），走正常轮次（审批照常）。
- [x] 已存在 AGENTS.md 时提示「已存在，将让模型更新它」再提交。
- [x] 测试：fake agent 下 `/init` 触发一轮且提示词含「AGENTS.md」。
- [x] `dart analyze` + `dart test` + `bash tool/build_binary.sh`，子模块提交 `feat(code): /init 生成项目 AGENTS.md`，父仓库提交 gitlink。

---

## M4：小命令批（spec #9/#10/#11/#12）

**目标：** `/compact`、`/cost`、`--version`、`--continue` 四个低成本命令面。

### 文件结构（M4）

| 文件 | 职责 |
|------|------|
| `lib/src/tui/tui_controller.dart` | `/compact` / `/cost` 实现 |
| `lib/src/tui/tui_commands.dart` | 命令表加两条 |
| `lib/src/budget/cost_tracker.dart` | `CostTrackerImpl` 加 token 计数只读 getter |
| `lib/src/version.dart` | **新文件**：`navaVersion`（`String.fromEnvironment`） |
| `tool/build_binary.sh` | 从 pubspec.yaml 抽版本传 `-DNAVA_VERSION=` |
| `lib/src/tui/tui_options.dart` | `--version` / `--continue` 解析 |
| `lib/src/tui/recent_session.dart` | **新文件**：`findRecentSessionId(sessionDir)` 按 jsonl mtime 取最新 |
| `bin/conatus_code.dart` | `--version` 打印；`--continue` 解析为 session |

### Task 1：`/compact`

**Files:** Modify `tui_controller.dart` / `tui_commands.dart`；Test `test/tui/tui_compact_command_test.dart`

- [x] `_handleCompact([String? note])`：取 `'compaction'` 服务、当前 session、`'llm'`；调 `compactIfNeeded(session, (events, previous) => summarizeEvents(llm, events, previous), keepRecent: 20)`（手动强制口径 20，小于自动预算时也能折；`summarizeEvents` 若未从 conatus_agent 导出则先补导出）。
- [x] 返回 `null` → 提示「历史太短，无需压缩」（Review Focus #5）；否则提示「已压缩 <compacted> 条早期事件」。
- [x] 测试：fake compactor 返回 null / 非 null 两路径；命令表含 compact。
- [x] `dart analyze` + `dart test` 通过，子模块提交 `feat(code): /compact 手动压缩`。

### Task 2：`/cost`

**Files:** Modify `cost_tracker.dart` / `tui_controller.dart` / `tui_commands.dart`；Test `test/tui/tui_cost_command_test.dart`

- [x] `CostTrackerImpl` 加 `promptTokens` / `completionTokens` 只读 getter。
- [x] `/cost`：读 `'costTracker'`，输出「今日估算成本：$x.xxxx（输入 N / 输出 M token，粗略护栏口径，非计费）」；服务缺失提示不可用。
- [x] 测试：注入预置用量的 tracker，输出含金额与 token 数。
- [x] `dart analyze` + `dart test` 通过，子模块提交 `feat(code): /cost 展示今日估算成本`。

### Task 3：`--version`

**Files:** New `lib/src/version.dart`；Modify `tui_options.dart` / `bin/conatus_code.dart` / `tool/build_binary.sh`；Test `test/tui/tui_options_test.dart`（补例）

- [x] `const String navaVersion = String.fromEnvironment('NAVA_VERSION', defaultValue: 'dev');`
- [x] `build_binary.sh`：`version="$(grep '^version:' "$package_root/pubspec.yaml" | awk '{print $2}')"`，`dart compile exe ... -DNAVA_VERSION="$version"`。
- [x] `TuiOptions` 加 `versionRequested`；bin 里打印 `nava <version>` 后退出（`dart run` 下为 `dev`，Review Focus #8）。
- [x] 检查根仓库 `Makefile` 打包目标是否也走 `build_binary.sh`，不是则同步加 `-D`。
- [x] 测试：解析 `--version`；`dart analyze` + `dart test` 通过，子模块提交 `feat(code): --version 与编译期版本注入`。

### Task 4：`--continue`

**Files:** New `lib/src/tui/recent_session.dart`；Modify `tui_options.dart` / `bin/conatus_code.dart`；Test `test/tui/recent_session_test.dart`

- [x] `Future<String?> findRecentSessionId(String sessionDir)`：列 `*.jsonl`，按文件 mtime 取最新且文件名（去扩展名）命中 `isCanonicalSessionId` 的；目录不存在/空 → `null`。
- [x] `TuiOptions` 加 `continueRequested`；bin：`--session` 优先，其次 `--continue` 解析（`null` 时 stderr 提示「没有历史会话，已新建」并走新建，Review Focus #6）。
- [x] 测试：临时目录造三个 jsonl（不同 mtime）取最新；空目录 → null；非 canonical 文件名跳过。
- [x] `dart analyze` + `dart test` + `bash tool/build_binary.sh`，子模块提交 `feat(code): --continue 恢复最近会话`，父仓库提交 gitlink。

---

## M5：意图路由 README 失真修正（spec #2 文档部分）

- [x] 决策执行：README 特性表删除「⚡ 意图路由（高频命令零模型调用）」条目（接线 `conatus_intent` 另立计划评估，本期只做文档求真）。
- [x] 子模块提交 `docs(code): README 移除未接线的意图路由宣传`，父仓库提交 gitlink。

---

## 后续另立计划/设计（本计划不覆盖）

| 项 | 前置 |
|----|------|
| ~~Checkpoint/rewind（spec #3）~~（**已实施** 2026-09-24，见专项 spec/plan） | 快照策略、与 Plan Mode/审批/沙箱的交互已在专项设计中定案 |
| ~~后台任务执行器（spec #4）~~（**已实施** 2026-09-24，三期） | `keep_alive_on_exit`（真 detach）与 conatus_tasks 深度接线另立 |
| ~~ASR 语音输入（spec #5）~~（**暂缓**，用户决定近期不做） | 音频设备依赖，单元测试策略先行 |
| observability 导出（spec #6） | 选导出后端（OTLP/文件） |
| `/commit`（spec #13） | 审批语义设计（staged diff → 提交信息） |
| Hooks（spec #14） | config  schema 与中间件挂点设计 |
| ~~消息排队（spec #15）~~（**已实施** 2026-09-24，三期） | TUI 输入状态机改动，与 Esc 打断交互 |
| `/doctor`（spec #16） | 无前置，可随时插入 |
| Linux/Windows 沙箱（spec #17） | 单独立项 |

## 里程碑提交序列（父仓库视角）

1. M1 完成 → `chore(code): 同步子模块 gitlink（MCP 接入）`
2. M2 完成 → `chore(code): 同步子模块 gitlink（headless 模式）`
3. M3 完成 → `chore(code): 同步子模块 gitlink（AGENTS.md 加载与 /init）`
4. M4 完成 → `chore(code): 同步子模块 gitlink（/compact、/cost、--version、--continue）`
5. M5 完成 → `chore(code): 同步子模块 gitlink（README 意图路由修正）`
6. 全部完成 → 本文件勾选归档，必要时更新 spec 状态为「已实施（一期）」。
