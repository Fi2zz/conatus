# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

- **破坏性变更**：移除 `ReadFileTool` / `provideFsTools`（`read_file` 工具层）。
  工具层迁往新包 `conatus_fs_tools`（`read_file` 增强为分页 + 行号，并新增
  `write_file` / `edit_file` / `rg` / `glob`）。本包回归纯 `fs` 接缝。
- 消息事件名 `kUserMessageEvent` / `kAssistantMessageEvent` / `kToolResultEvent`
  下沉到本包（会话词汇的拥有者），供压缩与 Agent Loop 共用；`conatus_agent`
  继续转出这些名字，既有导入面不变。
- `Session` 新增 `inheritedEventCount` 与 `ownEvents`：构造时可声明由种子继承的事件
  条数（`fork` 会自动把父会话事件标为继承前缀），派生状态因此只折叠本会话自有的后缀；
  `SessionStore.open` 载入的历史仍算自身事件。

## [0.15.0] — 2026-09-15

- 从 `conatus` 单体仓库拆分为独立包（pub workspace monorepo），
  承载 timer / logger / loader / tools / shell / fs / session /
  system-prompt / memory / database / ask-user 等基础设施插件。
