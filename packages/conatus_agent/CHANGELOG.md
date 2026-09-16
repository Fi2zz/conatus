# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

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
