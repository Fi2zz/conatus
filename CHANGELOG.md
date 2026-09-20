# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

`conatus_tui` 新增选项浮层与权限模式：

- `TuiChoicePrompt` / `TuiChoiceView`：可 `↑↓` 选择、`Enter` 确认、`Esc` 取消的
  浮层菜单，供模型提问与工具审批共用同一条通道
- `ask_user` 工具：模型给出候选选项交用户选择，选中项作为工具结果回传；
  `purpose: permission_mode` 时渲染内置的三档权限模式选项集
- 权限模式 `TuiPermissionMode`（始终询问 / 按需询问 / 从不询问）经
  `TuiPermissionGate`（`Approval` 实现）落到审批阈值；被拦截时弹出
  「允许一次 / 信任此文件夹 / 总是允许该工具 / 拒绝」，状态栏常显当前模式
- 「信任此文件夹」按「工具 + 目录」记住授权（判定走 `FileSystem.contains`）：
  该工具访问该目录及子孙免问，目录外或换工具仍要问
- 权限模式按会话持久化：`permission/mode` 事件追加进会话日志，切会话与重启
  各自恢复（`restorePermissionMode` 折叠自身后缀，fork 不继承）；信任记录
  随会话切换清空
- 装配变化：`ConatusTuiRuntime.create()` 现在会 `provideApproval` 并注册
  `ask_user`；此前 TUI 完全没有审批端口（`/plan` 的提示文案随之修正）

`conatus_foundation`：

- `Tool.pathParams`：声明工具哪些参数是文件系统路径；`tools.fn(..., pathParams:)`
  同步支持
- `Tool.timeout`：工具可声明自身超时，优先于注册表的 `defaultTimeout`
  （交互类工具如 `ask_user` 的耗时由用户决定，不应受默认超时约束）

`conatus_agent`：

- `ApprovalRequest.pathArgs`：请求携带其涉及的文件系统路径
- `Approval.preapproved(request)`：预授权钩子，中间件在询问前调用；返回 `true`
  直接放行，不产生请求、不发遥测、不弹界面
- `instrumentApproval` 路径感知：声明了路径参数的工具**即使低风险**也进入审批；
  导出 `pathArguments(tool, call)` 供实现方复用取值逻辑
- `provideApproval(..., instrument: false)`：只提供 `'approval'` 服务、不挂
  拦截，供阈值由别处动态决定的装配方自行调用 `instrumentApproval`

新增 `conatus_alerting` 包 —— 告警（实验性，不导出到伞包；依赖
`conatus_agent`、`conatus_core`、`conatus_foundation`、`conatus_tts`、`http`）：

- `Alert` / `AlertSeverity`（info / warning / critical）+ `AlertRule`（声明式
  条件 + 冷却期）+ `AlertContext`（滑动窗口统计 / 冷却状态 / 定期清理，
  时间来源可注入）
- `Alerting` / `provideAlerting`（服务键 `'alerting'`）：订阅 `Telemetry.events`
  逐规则判定，单规则异常隔离、通知失败不阻塞、`fire` / `resolve` / `activeAlerts` /
  `history` / `alerts` 流；关联 `sessionId` / `goalId`（从事件 data 提取）
- 默认规则集 8 条（LLM 慢 / 工具慢 / 工具连续失败 / Session 与当日预算 /
  Agent 轮次超限 / 子 Agent 卡住）；`RuleParser` 从 JSON 加载规则（字段比较 /
  窗口计数）
- 通知渠道（Seam）：`ConsoleNotifier`（缺省）/ `WebhookNotifier`（Slack 兼容）/
  `AskUserNotifier`（TTS 播报 + 口头响应回调）/ `CompositeNotifier` /
  `QuietHoursNotifier`（静默期 critical 例外）

新增 `conatus_browser_use` 包 —— 浏览器操作（实验性，不导出到伞包；依赖
`conatus_agent`、`conatus_core`、`conatus_credentials`、`conatus_foundation`、
`conatus_mcp`、`conatus_tasks`）：

- `BrowserUseRegistry` / `provideBrowserUse`（服务键 `'browserUse'`）：唯一
  Provider 注册（第二个注册失败、释放后可重注册）；浏览器绑定 Session，
  Session 释放时关闭其启动的资源，fork / 新 Session 经 `initializeBrowserFor`
  创建全新浏览器状态（登录状态不从 Session 日志恢复）
- `BrowserUseProvider` / `SessionBrowser` / `BrowserConfig`（launch / attach
  模式）：`PlaywrightMcpProvider`（默认，`npx @playwright/mcp`）与
  `ChromeDevToolsMcpProvider` 复用 `conatus_mcp` 客户端（transportFactory 可
  注入 Mock）；`StagehandProvider` 为骨架（需外部 SDK）
- `BrowserActionTool` 接入 ToolRegistry，风险分级（只读 low / 交互 medium /
  敏感 high）供审批门控；可选 seam：`taskCenter`（Task）、`approval`
  （高危操作审批）、Session Log（`browser/action` 事件）、`telemetry`
  （`browser.*` 埋点）

新增 `conatus_computer_use` 包 —— 桌面操作（实验性，不导出到伞包；依赖
同 `conatus_browser_use`）：

- `ComputerUseRegistry` / `provideComputerUse`（服务键 `'computerUse'`）：
  唯一 Provider 注册；**无 Session 所有权**（桌面是共享资源），启动失败释放
  此次尝试的注册、MCP 重连保留注册
- `ComputerUseProvider` / `DesktopSession` / `ScreenRegion` / `Screenshot` /
  `AttachmentStore`（含内存实现）：`CuaDriverMcpProvider`（默认，
  `cua-driver mcp`，断连标记后重连）与 `CuaDriverNativeProvider`（骨架）
- `ImageSupport` 图像路由：视觉模型接收持久化截图（挂附件存储回填
  `attachmentRef`），其余接收 MCP 图像诊断
- `DesktopActionTool` 接入 ToolRegistry：**所有输入操作一律 high 风险**走
  审批；可选 seam：`taskCenter`、`approval`、`sessionLog`（经
  `registerDesktopTools` 记录到触发它的 Session）、`telemetry`
  （`computer.*` 埋点）

新增 `conatus_tasks` 包 —— 任务中心（Task Center）：运行时的任务追踪中枢，
只回答「现在有哪些任务在跑、各自什么状态、能不能取消」，不负责调度与执行
（依赖 `conatus_agent`、`conatus_core`、`conatus_foundation`、`conatus_schedule`）：

- `TaskCenter` / `provideTaskCenter`（服务键 `'tasks'`）：任务树（`parentTaskId`）
  组织，`task/changed` 事件整值替换持久化到会话，恢复时按 id 折叠最后一个，
  未完成任务标记 failed（执行环境已丢失）
- 状态机：pending → running ⇄ paused → completed / failed / cancelled，
  终态不可再变更；`cancel` 级联取消活跃子任务并执行取消回调，shell 类任务
  走 approval 确认（缺省自动批准）；`task.*` 埋点（created / started /
  paused / resumed / completed / failed / cancelled）
- `provideTaskTracking`：运行时接入装饰器——Agent Loop 轮次钩子（新增
  `AgentLoop.turnTracker`，经 `ctx.inject` 后置挂载、依赖消失自动摘除）、
  `spawn_agent` 中间件（`ToolRegistry.use`，按结果值 `status` 判定子 Agent
  成败）、`TrackingShellExecutor`（shell 前后台执行追踪）、
  `trackScheduleDelivery`（提醒交付追踪）
- 模型工具 `list_tasks`（low，按状态/类型/父任务过滤，口语化播报）与
  `cancel_task`（medium，走审批）；不暴露 `create`——任务由运行时自动创建

`conatus_agent`：`AgentLoop` 新增可选生命周期钩子 `turnTracker`
（`AgentTurnTracker`：beginTurn / endTurn，一轮各一次，含 goalDriver 续行）。

新增 `conatus_cron` 包 —— 定时任务（dsh-cron 移植，不含 web 部分；依赖
`conatus_core`、`conatus_foundation`）：

- `CronService` / `provideCron`（服务键 `'cron'`）：任务规则四选一——`at` 一次性 /
  `every` 固定间隔（最小 10s）/ `daily` 本地 `HH:MM`（错过当天补发）/ `cron` 5 段
  表达式（Vixie 步进、标准 dom/dow 语义）；规则计算不读墙钟，注入 `clock` 可回放
- `CronStorage` 抽象端口 + `JsonCronStorage` 本地实现（原子 tmp+rename、损坏降级），
  宿主可实现同一接口接入任意后端；`configTasks` 静态任务运行时不可增删改
- `CronRuntime` / `provideCronRuntime`（服务键 `'cronRuntime'`）：tick 轮询（默认
  15s、3s 首 tick）+ 每任务隔离；到点经 `CronDelivery` 端口交付 `[cron]` framing，
  成功才消费时段、拒绝下个 tick 重试；装配方在 turn 结束后调 `finishRun` 推进
  `delivered` → `completed` / `failed`（摘要截断 300 字符），
  `systemCronNotifier()` 提供可选系统通知（macOS osascript / Linux notify-send）
- 运行历史 JSONL 封顶 500，任务与运行戳持久化——重启不重发已消费时段
- 模型工具 `cron_list` / `cron_add` / `cron_update` / `cron_remove` /
  `cron_history`；`conatus_tui` 已默认接上（交付进当前会话，收口回报运行状态）
- 未移植：管理抽屉、`/cron/api` HTTP 层及配套 trust fence

`conatus_tui`：`ConatusTuiRuntime.create` 新增 `baseDir` 参数（`sessionDir` /
`memoryFile` / cron 存储的缺省根，便于测试隔离）。

`conatus_tui`：`ConatusTuiController` 新增可选会话装配钩子 `configureSession`
（会话子上下文与内置插件就绪后回调，宿主可挂 `provideTaskCenter` /
`provideTaskTracking` 等会话级服务；缺省 null，行为不变）。

`conatus_tui`：新增 `/cron` 斜杠命令（不经模型管理定时任务：list / add /
remove / enable / disable / history；add 绑定当前会话，规则四选一
at / every / daily / cron）。

`conatus_foundation`：新增 `time-context` 插件，并把动态上下文接上消费点 —— 模型没有
时钟，相对日期（"明天""下周三"）与带本地语义的时刻（"明早九点"）都需要外部锚点：

- `SystemPrompt.renderContexts(assembly, {separator})`：拼接动态上下文并插值
  `{{variable}}`，空文本不贡献内容；`PromptContext` 此前只注册、不参与渲染
- `provideTimePrompt(ctx, {prompt, clock, zoneName})`：注册一份日粒度的
  `PromptContext`（ISO 日期 + 中文星期 + 时区），闭包每轮重新求值、跨天自动更新；
  `zoneName` 缺省取本地时区名；`formatClockOffset(duration)` 输出 `±HH:MM`
- 锚点只精确到日：system 是可缓存前缀，秒级变化会让前缀缓存每轮失效；精确到秒交给
  时间工具

`conatus_agent`：`buildSystemText` 按「段 → 动态上下文 → 历史摘要 → 当前计划 →
相关记忆」组装 system；没有注册任何上下文时输出与改动前逐字相同。

`conatus_tui`：装配时挂上 `provideTimePrompt`；`get_time` 改为返回带时区偏移的
RFC 3339（此前是无偏移的本地时间串，模型无法判断时区）。

`conatus_schedule`：`schedule_create` 的描述写明相对时长以创建时刻为基准、相对日期要
对齐 system 中的当前日期，意图模糊时先与用户确认而非自行编造延迟。

新增 `conatus_skill` 包 —— 技能加载（依赖 `conatus_core`、`conatus_foundation` 与
`yaml`；从 `deepseek-harness` 的 `packages/skill` 包族移植）：

- `SkillRegistry` / `provideSkillRegistry`（服务键 `'skillRegistry'`）：provider 与
  运行时技能的注册表，`available` 是同步快照，收集串行化并带合并窗口，
  单个 provider 失败只降级它自己（经 `onWarning` 上报）；`inlineSkills` 允许把
  一段提示词直接当技能注册（不落盘、不解析 frontmatter）
- `SkillFilesystemProvider` / `provideSkillFilesystem` / `SkillRootWatcher`：按
  rank 100/200/300/400/500 从 `<项目根>/.conatus/skills`、`.agents/skills` 与用户
  技能目录发现 `SKILL.md` / `<name>.md`，目录变更合并成一次失效
- `SkillCatalogSection` / `provideSkillCatalog`：把可用技能目录挂成 system prompt
  的 `skills` 段——没有技能时该段不存在，prompt 与本插件不存在时逐字相同
- `SkillLoadTool` / `provideSkillTool`：`skill` 工具按名字返回 `<skill_content>`
  正文块，结果由 Agent Loop 正常写进 `tool/result` 事件
- `parseSkillDocument`：真 YAML frontmatter，`name` / `description` 必需，
  旧 camelCase 键与非法条目一律丢弃并告警
- 命名与 `conatus_agent` 的 `SkillLibrary`（服务键 `'skill'`，技能沉淀）刻意区分；
  `conatus_tui` 缺省接上（`ConatusTuiRuntime.create(skills: false)` 可关）

新增 `conatus_compaction` 包 —— 压缩能力缝（依赖 `conatus_core`、
`conatus_foundation`；压缩实现从 `conatus_agent` 迁入，对应 dsh
`packages/compaction/compaction`）：

- `CompactionEngine`（服务键 `'compaction'`）：`compactIfNeeded` / `summaryOf` /
  `forget` / `keepRecent`；`Compactor` 为默认实现，`provideCompaction` 负责装配；
  `LayeredCompactor` 留在 `conatus_agent`，按类别分层折叠（改为实现同一契约）
- 压缩在日志末尾追加 `compaction/start` → `compaction/summary` →
  `compaction/end` 三个纯记录事件：滚动摘要因此可从日志重建，补上「模型可见即已
  记录」的缺口；`checkCompactionInvariant` 校验这三个事件成对、同身份，且折叠区间
  是日志开头的一段
- 压缩切点吸附到不劈开助手工具调用与其 `tool/result` 的最近位置
  （`balancedCutAtOrBefore` / `toolPairingBalancedBefore` / `toolPairingBalancedAfter`），
  保留窗口不再可能以孤立的工具结果开头
- `Summarizer` 的产出改为 `CompactionSummary`，`summarizeEvents` 一并返回写摘要的
  provider / model，随 `compaction/summary` 落日志
- `conatus_foundation` 接管消息事件名 `kUserMessageEvent` /
  `kAssistantMessageEvent` / `kToolResultEvent`（会话词汇下沉，`conatus_agent`
  继续转出，导入面不变）

新增 `conatus_schedule` 包 —— 会话本地持久提醒（依赖 `conatus_core`、
`conatus_foundation` 与 `timezone`）：

- `SessionSchedule` / `provideSessionSchedule`（服务键 `'schedule'`，`ctx.schedule`）——
  提醒写在会话事件流的 `schedule/change` 事件里（严格版本 1 解码：拒绝未知版本、
  额外字段、id 复用与指向非活动记录的转换），因此会话落盘后重启即可自动重建；
  `provideScheduleTools` 注册 `schedule_create` / `schedule_list` /
  `schedule_delete` 三个工具
- `ScheduleRuntime` / `provideScheduleRuntime`（服务键 `'scheduleRuntime'`）——
  到期后折叠、采样墙钟并调用注入的交付端口；交付失败不写派发记录、记录保持活动，
  追加失败则停止派发（消息可能已经入队）；重试由活动驱动，不额外起私有定时器
- `at` 支持显式偏移的 RFC 3339 串与 `{date, time, time_zone}` 对象（IANA 时区，
  夏令时缺口拒绝、重叠取较早）
- `foundation` 的 `Session` 新增 `inheritedEventCount` / `ownEvents`：fork 出的会话
  不继承父会话的活动状态，而 `SessionStore.open` 载入的历史仍算自身事件
- TUI 的会话子上下文装配提醒服务、工具与运行时；轮次结束即触发一次到期推导

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
- `conatus_compaction` — 压缩能力缝（滚动摘要 + `compaction/*` 日志事件）
- `conatus_agent` — Agent Loop 与产品化（plan / sub-agent / reflection /
  telemetry / eval / approval / skill / recovery）
- `conatus` — 伞包，再导出以上全部，保持 `package:conatus/conatus.dart` 兼容

`conatus_cron`：通知收敛为纯抽象端口 —— `cron_notify.dart` 只保留 `CronNotifier`
类型，移除 `systemCronNotifier` / `mobileCronNotifier` 导出与条件导出实现
（mobile_notifier_*）；macOS / Linux 桌面实现移交 conatus_tui
（`systemCronNotifier()`，osascript / notify-send）

`conatus_cron`：`CronDelivery` / `CronNotifier` 端口各增加第三个参数 `task`
（原始任务），调用方可基于任务自行决定如何渲染投递 / 通知内容；`fire` /
`finishRun` 分别携带对应任务（通知永远发，任务已删除时 `task` 为 null，
由调用方决定后续处理）

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
