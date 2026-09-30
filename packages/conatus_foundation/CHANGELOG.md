# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

- **行为变更**：`ToolRegistry` 的超时预算（`defaultTimeout` / `Tool.timeout` /
  `call(timeout:)`）改为**只包住工具体**，不再包住整条中间件链。
  - 原先超时套在链外，最外层中间件若是审批门控（`instrumentApproval`，其自身
    预算是 5~30 分钟）就会被工具预算截断：用户批准后工具照样执行，结果却被丢弃
    并上报 `TOOL_TIMEOUT`——写操作于是变成「模型以为失败而重试、实际写了两遍」。
  - 现在各中间件需自备边界（`conatus_agent` 的 lint 有 30s、MCP 请求有 30s），
    工具干活由注册表的预算兜底。超时行为对纯工具调用无变化。


- **行为变更**：`JsonDatabaseBackend` / `JsonlSessionPersistence` 的缺省目录由
  `<cwd>/.conatus/{database,sessions}` 迁至 `$CONATUS_HOME/{database,sessions}`
  （缺省 `~/.conatus/...`）；新增 `resolveConatusHome` / `resolveHomeDir` /
  `kConatusHomeEnv` 出口。用户目录无法定位（无 `HOME` / `USERPROFILE`）时抛
  `StateError`，不再回退当前工作目录；旧 `<cwd>/.conatus` 数据保留不删、
  不自动迁移。
- `SessionStore.create()` 缺省 id 改为 `session_<uuid>`（新增 `newUuidV4()`
  生成 UUID v4）；不再使用 `session-<微秒>-<序号>` 格式。
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
