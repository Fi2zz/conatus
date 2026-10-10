# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

- **进程树终结（E-15）**：新增 `killProcessTree`（`process_kill.dart`）——用
  `pgrep -P` 递归收后代、先后代后根，修复「`bash -c "a & b"` 杀掉 bash 后孙
  进程孤儿化继续跑」；`LocalShellExecutor` 的后台 `kill`、前台超时、取消信号
  均改走它。

- **安全（E-13）会话 JSONL 落盘权限收紧**：`JsonlSessionPersistence` 首写即把
  会话文件设为 0600（属主读写），不再随 umask（通常 0644）暴露给同机其他用户；
  新增 `restrictFilePermissions` / `restrictDirectoryPermissions`
  （`file_permissions.dart`）作为通用落盘权限缝（文件 0600 / 目录 0700），
  语义与 conatus_code 对 config.toml 的 600 策略一致。会话文件含完整对话与
  工具输出（用户可能粘贴过密钥），旧版本遗留的 0644 文件会在下次追加时补收紧。
  权限收紧改用「读当前权限位」判定而非内存集合，chmod 失败不会留下「已收紧」
  假记录；chmod 返回非 0（只读文件系统 / 权限不足）同样抛错，不静默放过。

- `ToolRegistry.use` 新增可选 `tag`；`copyPipelineTo` 新增 `excludeTags`，供受限
  子注册表按类排除中间件（如子代理自带审批策略时排除宿主审批层，避免双层审批）。

- `ToolRegistry.copyPipelineTo`：把守卫与环绕中间件复制到另一个注册表（不复制工具
  与结果监听器），供「受限子注册表」复用宿主同一条执行管线。

- 修 `LocalFileSystem` 对**尚未创建的深层路径**的键：此前目标不存在时只对父目录
  取真实路径，父链中间还有未创建目录时会退回字面路径，违反「同一文件同一键」
  的契约。macOS 上 `/var`、`/tmp` 是 `/private/...` 的别名，于是「根已规范化 +
  目标未规范化」会让沙箱文件 jail（`JailedFileSystem`）把工作区内的新文件误判
  越界。现对**最长的已存在祖先**取真实路径再拼回余下段（与 dart_io_sandbox 的
  `canonicalizePath` 同语义）。

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
