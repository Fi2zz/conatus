# conatus_computer_use

> ⚠️ **实验性**：本包处于早期探索阶段，API 可能在没有 major 版本号变更的情况下
> 发生破坏性改动，请勿在生产环境依赖它。不进 `conatus` 伞包（`publish_to: none`），
> 使用方需显式依赖。

conatus 的计算机操作能力：让模型通过配置的 Provider **观察并操作本地桌面**
（截屏、移动鼠标、点击、输入）。与 `conatus_browser_use`（操作网页）互补。

## 与 browser-use 的关键区别

| 维度 | browser-use | computer-use |
|------|-------------|--------------|
| 操作对象 | 网页（DOM、页面导航） | 本地桌面（屏幕、鼠标、键盘） |
| Session 所有权 | **严格**：浏览器绑定 Session | **无**：不预留桌面，调用方协调 |
| 跨轮次状态 | 保留（同一 Session 复用浏览器） | 不保留 |
| 取消语义 | 无法撤销已交付的操作 | **无法撤销桌面已收到的输入** |
| 验证方式 | DOM 变化可断言 | 像素级，需图像比对 |

**最重要的区别**：computer-use **没有 Session 级别的桌面所有权**——桌面是共享
资源，多个 Agent 可能同时操作同一个桌面，无法像浏览器那样为每个 Session 隔离。
调用方负责协调跨 Session 的完整观察、操作与验证流程。

## 用法

```dart
// 依赖：tools 必需，其余 seam 可选
provideTools(app);
provideComputerUse(
  app,
  provider: CuaDriverMcpProvider(
    command: 'cua-driver',
    args: <String>['mcp'],
  ),
  taskCenter: ...,       // 桌面操作作为 Task
  approval: ...,         // 所有输入操作审批（缺省自动批准）
  telemetry: ...,        // 埋点
);
```

桌面工具（`screen_capture` / `mouse_click` / `keyboard_type` / `scroll` 等）注册进
`ctx.tools`，模型可直接调用。若要把操作记录到触发它的 Session 日志，用
`registerDesktopTools`（带上 `sessionId` 与 `sessionLog`）。

## 核心类型

- `ComputerUseRegistry`（服务键 `'computerUse'`，由 `provideComputerUse` 提供）：
  只注册 Provider **名字**，拒绝第二个注册（包括同名实例）；释放后可重新注册。
- `ComputerUseProvider`：`initialize()`（返回**不绑定任何 Session** 的
  `DesktopSession`）/ `dispose()`。
- `DesktopSession`：`toolNames` / `call(tool, args)` / `capture({region})` /
  `close()`。工具 schema、结果渲染、图像支持由 Provider 拥有。
- `ScreenRegion` / `Screenshot`：屏幕区域与截图值类型（`isEmpty`、`copyWith`、
  JSON 往返）。
- `AttachmentStore` / `InMemoryAttachmentStore`：持久化截图（`save` / `load` /
  `delete`）。

## 生命周期

```
initialize()
    │
    ├── 成功 → 保留注册（装配层）
    │
    └── 失败 → 释放此次尝试的注册（可重新尝试）

MCP 断连 → 保留注册（不释放）；标记断连，再次 initialize() 重建客户端

dispose() → 先停工具，等待自有工作完成，再释放注册
```

## 图像路由

支持图像的模型路由在挂载附件存储时接收**持久化截图**（`capture` 回填
`attachmentRef`）；不支持图像的路由接收**现有 MCP 图像诊断**（文本描述）。

```dart
imageSupportFor('doubao', 'doubao-seed-1-8-251228'); // ImageSupport.persistent
imageSupportFor('deepseek', 'deepseek-chat');        // ImageSupport.diagnostic
```

## 工具集与风险分级

| 风险 | 工具 |
|------|------|
| `low`（只读） | `screen_capture` / `screen_list` / `cursor_position` / `window_list` |
| `high`（**所有输入操作**） | `mouse_move` / `mouse_click` / `mouse_drag` / `keyboard_type` / `keyboard_press` / `keyboard_hotkey` / `scroll` / `window_focus` |

与 browser-use 不同，桌面操作**无法区分** `medium`——任何输入都可能产生不可逆的
后果，因此所有输入操作一律 `high` 风险，走审批。

## Provider

| Provider | 集成方式 | 说明 |
|----------|----------|------|
| `CuaDriverMcpProvider`（默认） | MCP（stdio） | `cua-driver mcp`，复用 `conatus_mcp` 客户端，Cua Driver 可独立升级 |
| `CuaDriverNativeProvider` | 原生（骨架） | 平台原生运行时随 npm 依赖安装，**暂未接入**，`initialize` 抛 `UnsupportedError` |

MCP Provider 支持 `transportFactory` 注入 Mock Server（测试用），`timeout` 默认
30s。

## 运行时 seam（全部可选注入）

| seam | 用途 | 缺省行为 |
|------|------|----------|
| `tools` | 注册桌面操作工具 | 必需（缺省取 `ctx.tools`） |
| `taskCenter` | 桌面操作作为 Task（`kind: custom`） | 不追踪 |
| `approval` | 所有输入操作审批（挂标准 `instrumentApproval`，threshold high） | 自动批准 |
| `telemetry` | 埋点（`computer.provider.registered` / `computer.provider.released` / `computer.action.*`） | 无埋点 |
| `sessionLog` | 操作记录（经 `registerDesktopTools` 绑定触发它的 Session） | 无记录 |
| `attachmentStore` | 持久化截图（`CuaDriverMcpProvider` 构造参数） | 截图不持久化 |

## 注意与限制

- **无 Session 所有权**：Provider 不为某个 Session 预留桌面；取消调用**无法撤销**
  桌面已收到的输入。
- **唯一 Provider**：共享服务只注册一个 Provider，第二个注册（含同名）失败。
- **能力约束**：browser_use 的 `low` / `medium` / `high` 分级在此不适用——所有输入
  操作都是 `high`。
- **语音场景**：智能音箱用户看不到屏幕，每一步操作都要口头描述、高危操作必须走
  审批、完成后要有明确验证；语音交互属于上层装配（`approval` seam 组合
  `VoiceApproval`），本包不引入 tts / asr 依赖。
- 依赖方向：`conatus_computer_use → conatus_mcp / conatus_agent → conatus_core`，
  反向不成立；`conatus_agent` / `conatus_mcp` 不依赖本包。
- 设计细节见仓库根 `handoff-computer-use.md` 与 `.handoffs/HANDOFF-10.md`。
