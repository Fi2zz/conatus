# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

`llm` 流式补全补齐 function calling：

- `LlmProvider.chatStream` / `FallbackLlm.chatStream` 新增 `tools` 参数，与非流式
  `chat` 语义一致，透传工具 schema
- 流式解析累积工具调用分片（Chat Completions 按 `tool_calls[].index`、
  Responses 按 `output_item` / `function_call_arguments`），在终态
  `LlmStreamDone.toolCalls` 一次性给出完整调用

仓库重组为 pub workspace monorepo，按依赖层次拆包：

- `conatus_core` — `Context` / `EffectScope` / `Reactor`（零运行时依赖）
- `conatus_foundation` — timer / logger / loader / tools / shell / fs /
  session / system-prompt / memory / database / ask-user
- `conatus_llm` — 大模型接入（豆包 / DeepSeek）
- `conatus_search` — 搜索能力缝 + `web_search` / `fetch_url`
- `conatus_agent` — Agent Loop 与产品化（plan / sub-agent / reflection /
  telemetry / eval / approval / skill / recovery）
- `conatus` — 伞包，再导出以上全部，保持 `package:conatus/conatus.dart` 兼容

## [0.15.0] — 2026-09-15

新增技能沉淀与持久化恢复（handoff2 第 12、17 步）：

- `skill` — `SkillLibrary` / `provideSkillLibrary`（服务键 `'skill'`，`ctx.skills`）：
  记录工具轨迹，同一序列出现 `threshold`（默认 3）次后用 `SkillNamer`
  （`llmSkillNamer` / `deterministicSkillNamer`）命名，构造 `SkillTool` 注册；
  `SkillTool` 按序执行步骤并支持 `{{param}}` 占位符；含 `high` 风险步骤不沉淀，
  启用前若配了 `Approval` 需获批，技能可存入 `MemoryStore` 并 `restore`
- `recovery` — `RecoveryService` / `provideRecovery`（服务键 `'recovery'`）：
  `snapshot(session)` 存带版本号的 `SessionSnapshot`（计划在事件里），
  `restore(id)` 还原会话继续对话；`SnapshotStore` 端口 + `DatabaseSnapshotStore`
  （JSON 后端）/ `MemorySnapshotStore`；版本不符抛 `unsupported-version`
- 为控制行数把 Agent 事件派生/上下文装配拆到 `agent_events.dart`

## [0.14.0] — 2026-09-15

新增高危工具审批（handoff2 第 15 步）：

- `approval` — `Approval` 端口 + `ApprovalRequest`；内置 `AutoApproval`（测试/开发）、
  `RuleBasedApproval`、`AskUserApproval`（经 `ask_user`，超时视为拒绝）；
  `requestPlan(plan)` 一次性审批整份计划
- `instrumentApproval` 挂到工具调用链：风险不低于阈值（默认 `high`）的工具先审批，
  拒绝/超时返回 `APPROVAL_DENIED`；`provideApproval` 一次装好服务与拦截
- 有 `'telemetry'` 时记录 `approval.requested` / `approval.decided` 审计事件

## [0.13.0] — 2026-09-15

新增评估体系（handoff2 第 14 步）：

- `evaluation` — `EvalCase` / `EvalResult` / `EvalReport` / `EvalDiff`；
  `Evaluator({run, judge})` 注入 `EvalRunner` 跑用例，`defaultEvalJudge` 判分
  （期望工具子集 + 输出关键词 + 步数上限）；`EvalReport.compareTo` 给出通过率与
  平均步数差；`EvalCase` / `EvalReport` 支持 JSON 往返，便于持久化基线

## [0.12.0] — 2026-09-15

新增可观测性（handoff2 第 13 步）：

- `telemetry` — `Telemetry` 端口 + `InMemoryTelemetry`（内存缓冲 + 广播流）/
  `ConsoleTelemetry`；`provideTelemetry` / `ctx.telemetry`
- 埋点装饰器：`instrumentTools`（工具中间件 `tool.called` / `tool.failed`）、
  `TelemetryLlmProvider`（`llm.request` / `llm.failed`）；`AgentLoop.onEvent`
  产出 `agent.round` / `agent.finished`，`provideAgentLoop` 检测到
  `'telemetry'` 时自动包模型与接事件

## [0.11.0] — 2026-09-15

新增子 Agent 委托与工具后自省（handoff2 第 10、11 步）：

- `sub-agent` — `SpawnAgentTool`（`spawn_agent`）/ `provideSpawnAgent`：在宿主
  上下文下派生隔离子上下文与独立 `Session`，用受限 `ToolRegistry`（显式白名单
  或「非 high 且非自身」默认白名单）跑独立 `AgentLoop`，只回传
  `{status, output, rounds, tool_calls}`；宿主释放时在途子 Agent 终止
- `reflection` — `Reflector` / `provideReflection`：工具执行后用一次独立 LLM 调用
  判断「继续 / 重试 / 重新规划」；`ReflectionStrategy`（`always` / `onError` /
  `onRisk` / `never`，或上下文 `'reflectionStrategy'`）；`reflectAndRetry` 有界
  重试、`replan` 触发重新规划；`AgentLoop` 自动接入 `'reflection'`

## [0.10.0] — 2026-09-15

新增工具结果驱逐与规划（handoff 第 8、9 步）：

- `fs` — 契约补 `remove(target)`（本地实现删除文件/目录，目标不存在静默）
- `fs` 工具 — `ReadFileTool`（`read_file`）/ `provideFsTools`
- `tool-result-eviction` — 超阈值工具结果落盘，正文替换为「前 N 字符 + 省略提示 +
  后 N 字符 + 路径」；失败结果不驱逐；阈值取参数或上下文 `'toolResultThreshold'`；
  临时文件随上下文释放清理；`ToolResultEviction.evict/clear/spilledPaths`
- `plan` — `Plan` / `PlanStep` / `PlanTool`（`plan_write`）；计划以 `plan/updated`
  事件持久化进会话，`readPlan` / `writePlan` / `planSection` 读写；`runPlanningPhase`
  跑一次「只允许 plan_write」的规划轮；`AgentLoop(planning: true)` 无计划时先规划，
  执行轮把 `[当前计划]` 注入 system

## [0.9.0] — 2026-09-15

新增 Agent Loop，并给 `llm` 补上 function calling：

- `llm` — `LlmToolCall`；`LlmMessage` 支持 `toolCalls` / `toolCallId`；
  `LlmResult.toolCalls`；`chat(messages, {tools})` 下发工具 schema 并解析
  tool_calls（Chat Completions 与 Responses 双形态，含 `function_call` /
  `function_call_output` 序列化）；`FallbackLlm implements LlmProvider`
- `agent` — `AgentLoop` / `provideAgentLoop`（服务键 `'agentLoop'`，`ctx.agentLoop`）：
  一轮 `run(userInput)` 写入用户事件并压缩上下文 → 组装 system（`SystemPrompt`
  装配 + 历史摘要 + `MemoryStore` 召回）+ 会话事件派生的历史 → 调模型 → 执行
  工具调用并回填 → 纯文本收口（写会话 + 记长记忆）
- 会话事件 `user/message` / `assistant/message` / `tool/result` 与
  `deriveAgentMessages` 还原；`summarizeEvents` 为默认压缩汇总器
- 工具失败作为失败结果回填不中断；会话在循环中被关闭则中止；有界多步 `maxSteps`
- 示例更新为「提问 → LLM → 工具调用 → 回填 → 回复」完整闭环

## [0.8.0] — 2026-09-15

重构 `tools` 为完整的工具层，并新增 `search` 能力缝与 web 工具：

- `Tool` 基类 + `ToolContext` + `ToolResult`：作者继承声明形状（含预留的
  `riskLevel` / `group`）并实现 `call`，`ToolContext` 提供类型安全取参
- `ParamSpec` + `parameterSchema`：string / integer / number / boolean / enum /
  array / object 参数声明自动编译为 JSON Schema，`Tool.toSchema()` 直接消费
- `ToolRegistry`：`ctx.tools` 快捷访问；`call` 先按参数声明校验，再经过守卫与
  中间件调用执行体，超时（`TOOL_TIMEOUT`）、参数不合法（`INVALID_ARGS`）、未知
  工具（`UNKNOWN_TOOL`）与异常（`TOOL_ERROR`）都收敛为失败结果；`describe()` /
  `describeOne()` 返回白名单 schema
- `ctx.tools.fn(...)`：一行注册简单工具
- `ctx.tools.group(name, [...])` + `Tool.riskLevel` / `guardRisk` / `describeWithin`：
  按领域分组与能力分级（分组状态经 `Expando` 存放，不改 `ToolRegistry` 本体）
- `search` 插件：`ctx.search` provider 回退链；默认 `DuckDuckGoSearchProvider`
  （无需 Key），`ExaSearchProvider` 在提供 Key 时优先；`WebSearchTool` /
  `FetchUrlTool` 经 `provideWebTools` 注册进 `ctx.tools`

（原 `ToolDefinition` / `ToolHandler` 由 `Tool` 基类取代；`execute` 更名 `call`，
`schemas` 更名 `describe`。）

## [0.7.0] — 2026-09-15

新增 `database` KV 存储插件（hub + 可插拔后端 + 本地 JSON 实现）：

- `Database` / `provideDatabase`（服务键 `'database'`）：具名后端注册
  （`register` / `backend` / `backendNames`）、单元打开（`open` / `get` / `units`）
  与关闭（`close` / `closeAll`）；未指定路由时用 `defaultBackend`，仅注册一个
  后端时自动选中
- `DatabaseUnit`：同步读（`get` / `has` / `keys` / `entries`）、异步写
  （`put` / `delete`）与变更广播（`onChange`）；写入先落盘、成功后才更新内存并
  发出 `DatabaseChange`，读到的内存状态永不领先介质
- `DatabaseBackend` 端口 + `JsonDatabaseBackend` / `provideDatabaseJson`：
  每单元一个 JSON 文件，临时文件 + rename 原子发布，非对象内容判为
  `malformed-medium`
- 错误统一由 `DatabaseException` 携带错误码（`backend-not-found` /
  `already-open` / `unit-closed` / `no-backend` 等）

## [0.6.0] — 2026-09-15

新增会话、上下文管理与长记忆四组插件：

- `session` — append-only 会话事件日志 `Session`（`append` / `events` / `onEvent` /
  `onClose`）、会话仓库 `SessionStore` / `provideSessions`，以及可插拔持久化端口
  `SessionPersistence` / `provideSessionPersistence` 与本地 JSONL 实现
  `JsonlSessionPersistence`
- `system-prompt` — prompt 段与动态上下文的注册表 `SystemPrompt` /
  `provideSystemPrompt`：`section` / `context` / `assemble` / `render`（含
  `{{variable}}` 插值）
- `compaction` — 会话滚动摘要 `Compactor` / `provideCompaction`：超过 `keepRecent`
  时把较早事件连同上一版摘要交给注入的 `Summarizer` 折叠
- `memory` — 长记忆库 `MemoryStore` / `provideMemory`：`remember` / `recall` /
  `forget` / `clear`、中英文关键词打分、容量治理；存储端口 `MemoryBackend` 与
  `InMemoryMemoryBackend` / `JsonMemoryBackend` 两种本地实现

## [0.5.0] — 2026-09-15

新增工具与两个能力缝（Service Definition + 本地 Provider）：

- `tools` — 工具注册表 + 受控执行管线（`ToolRegistry` / `provideTools`）：
  `register` / `get` / `schemas` / `guard` / `use` / `onChange` / `onResult` /
  `execute`；未知工具、守卫拒绝、执行体抛错都收敛为失败结果
- `shell` — 命令执行能力缝（`ShellExecutor` / `provideShell`）与本地实现
  `LocalShellExecutor` / `provideShellLocal`：前台 `run`（超时、stdout/stderr
  采集与截断）与后台 `start`（增量 `readOutput` / `kill`）
- `fs` — 文件系统能力缝（`FileSystem` / `provideFileSystem`）与本地实现
  `LocalFileSystem` / `provideFileSystemLocal`：稳定目标身份、`stat` / `lstat` /
  `readText` / `listDir` / 原子 `writeText` / `editText`，写入意图守卫
  （`FsCreateIfAbsent` / `FsReplaceIfVersion`）与稳定的 `FsErrorCode`

两个能力缝都只定义契约，消费方依赖抽象，替换为沙箱 / 远程后端时不改代码。

## [0.4.0] — 2026-09-15

新增三个基础设施插件：

- `timer` — 定时器作为 Context 的可逆效应（`TimerContext` 扩展）：
  `timeout` / `interval` / `sleep` / `throttle` / `debounce`，随上下文释放自动清理
- `logger-console` — 自带 `LoggerService`（分级、命名 logger、可插拔导出器）
  与 `ConsoleExporter`，入口 `provideLogger`
- `loader` — 注册表 + 配置树的装载器：`register` / `apply` / `load` / `remove` /
  `reload`，支持分组与 JSON 配置（`LoaderEntry`）

Dart 没有动态 `import()`，loader 以**按名注册的插件工厂**代替模块解析。

## [0.3.0] — 2026-09-15

`llm` 插件补齐 Responses 形态与流式：

- `LlmApiStyle` — `chat`（`/chat/completions`，默认）/ `responses`（`/responses`）
- `DoubaoProvider` / `DeepSeekProvider` 新增 `apiStyle` 参数（默认 `chat`，
  原有调用行为不变）；Responses 形态显式 `store: false`
- `LlmProvider.chatStream` — 双形态 SSE 流式解析，事件为 `LlmTextDelta` /
  `LlmReasoningDelta` / `LlmStreamDone`（累计用量与结束原因）
- `FallbackLlm.chatStream` — 流式自动回退（仅在该提供商尚未产出增量时回退）
- `LlmProvider.close()` — 统一资源释放；`FallbackLlm.close()` 逐个关闭

### 调整

- OpenAI 兼容的 wire 层拆到 `lib/src/plugins/llm_openai.dart`；
  `llm.dart` 保留协议类型、回退链与插件入口

## [0.2.0] — 2026-09-14

新增两个内置插件：

- `ask_user` — 在上下文中声明式地向用户提问，支持 CLI 交互与自定义提问器
  - `AskUser` 接口 + `CliAskUser` 默认实现
  - `provideAskUser` 注册服务，上下文释放时自动取消提问
- `llm` — 统一的大模型接入层
  - `DoubaoProvider`（豆包，首选）/ `DeepSeekProvider`（备选）
  - `FallbackLlm` 自动回退，全部失败时汇总错误
  - `provideLlm` 注册服务，上下文释放时自动关闭 HTTP 客户端

## [0.1.0] — 2026-09-14

首个版本，基于论文
*A Programming Paradigm for Spatiotemporal Composability*
（arXiv:2608.25512）的核心机制实现。

### 新增

- `EffectScope` — 可逆效应的收集与 LIFO 撤销（时间可组合性）
- `Reactor` — 服务变更的同步广播，含重入收敛与循环依赖检测（空间可组合性调度）
- `Context` — 统一上下文，同时承载效应与共效应
  - `provide` / `get` / `require` / `has` — 服务注册与沿父链查找
  - `track` / `effect` / `onDispose` — 可逆副作用登记
  - `inject` — 声明式依赖注入，依赖变化时自动激活/停用
  - `plugin` — 插件的加载与卸载单元
- 覆盖全部核心路径的单元测试
- GitHub Actions CI（stable / beta 双 SDK）
