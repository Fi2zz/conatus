# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

- **子 Agent（`spawn_agent`）接上历史压缩器**：`SpawnAgentTool` / `provideSpawnAgent`
  新增 `compactor`，缺省在 `run` 内从宿主上下文惰性解析 `'compaction'`（装配顺序上
  `provideSpawnAgent` 早于 `provideCompaction`，注册期取不到，故不能提前取）。
  此前子 `AgentLoop` 不接 compactor、又不带主注册表的工具结果驱逐中间件，
  `read_file` 单次上限 20 万字符一叠加就顶爆模型窗口，子任务以 `status=failed`
  收场且白烧前面的 token；压缩让长调研子任务能继续。
- **子工具白名单统一按风险过滤**：显式 `tools` 参数此前只按存在性筛选，模型可以
  `spawn_agent(tools: ["run_command"])` 让子 Agent 拿到 high 工具。子注册表是新建
  的、不带主注册表的审批中间件，等于绕过人工确认。现在显式与 `defaultTools` 两路
  都排除 high（与框架缺省路径一致），`_allowedTools` 的判定收进 `_usable`。

- `AgentLoop.run` 新增可选 `images` 参数：随用户消息发给模型，并写入
  `user/message` 事件（`images` 字段，base64）；`deriveAgentMessages` 回放、
  历史压缩与「模型可见即已记录」不变式均支持图片

- 压缩实现迁到 `conatus_compaction`：`Compactor` / `CompactionResult` /
  `Summarizer` / `provideCompaction` 由该包提供，`AgentLoop` /
  `provideAgentLoop` / `compactSession` / `buildSystemText` 改为依赖
  `CompactionEngine`（服务键不变，仍是 `'compaction'`）
- `LayeredCompactor` / `provideLayeredCompaction` 留在本包：不做日志记录、切点与
  摘要记忆（由 `Compactor` 承担），只覆盖 `summarizeFolded` 做按类别分层折叠
- `summarizeEvents` 返回 `CompactionSummary`（摘要文本 + 写它的 provider / model）
- `compactSession` 按实际折叠条数返回历史窗口起点（安全切点可能比预算切点更靠前）
- 消息事件名 `kUserMessageEvent` / `kAssistantMessageEvent` / `kToolResultEvent`
  改由 `conatus_foundation` 拥有，本包继续转出，导入面不变

## [0.15.0] — 2026-09-15

- 从 `conatus` 单体仓库拆分为独立包（pub workspace monorepo），
  承载 `AgentLoop` 与 plan / sub-agent / reflection / telemetry /
  evaluation / approval / skill / recovery / tool-result-eviction。
