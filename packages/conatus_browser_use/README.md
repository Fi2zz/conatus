# conatus_browser_use

> ⚠️ **实验性**：本包处于早期探索阶段，API 可能在没有 major 版本号变更的情况下
> 发生破坏性改动，请勿在生产环境依赖它。不进 `conatus` 伞包（`publish_to: none`），
> 使用方需显式依赖。

conatus 的浏览器操作能力：让模型通过配置的后端**检查与操作网页**。`web_search`
只返回搜索摘要、`fetch_url` 只返回文本——它们都是**只读的**；browser_use 补上的是
**交互能力**（填表单、点按钮、翻页、等待异步加载），让 Agent 从「能读网页」到
「能用网页」。

## 用法

```dart
// 依赖：tools 必需，其余 seam 可选
provideTools(app);
provideBrowserUse(
  app,
  provider: PlaywrightMcpProvider(
    command: 'npx',
    args: <String>['-y', '@playwright/mcp@latest'],
  ),
  session: session,      // 浏览器绑定 Session（可选；fork 后用 initializeBrowserFor）
  taskCenter: ...,       // 浏览器操作作为 Task
  approval: ...,         // 高危操作审批（缺省自动批准）
  telemetry: ...,        // 埋点
);

// fork 出新 Session 时创建全新浏览器状态（登录状态不从 Session 日志恢复）
await initializeBrowserFor(app, newSession);
```

浏览器工具（`browser_navigate` / `browser_click` / `browser_type` / `browser_evaluate`
等，名字与 schema 由 Provider 拥有）注册进 `ctx.tools`，模型可直接调用。

## 核心类型

- `BrowserUseRegistry`（服务键 `'browserUse'`，由 `provideBrowserUse` 提供）：
  只注册 Provider **名字**，拒绝第二个注册（包括同名实例）；释放后可重新注册。
- `BrowserUseProvider`：`initializeFor(Session)` / `release(Session)` / `dispose()`。
  同一 Provider 实例内，一个浏览器只能被一个 Session 拥有。
- `SessionBrowser`：绑定 Session 的浏览器实例，跨轮次复用；`toolNames` /
  `call(tool, args)` 由 Provider 决定。
- `BrowserConfig`：启动模式（`launch` 启动新浏览器 / `attach` 附加已有浏览器，
  释放时只断开不关闭）、`headless`（默认 true）、`profile`、`viewport`、`userAgent`。

## Session 所有权与 fork

- 浏览器绑定使用它的**确切实时 Session**：Session 释放时关闭其启动的资源；
- 重新加载或 fork Session 时创建**全新浏览器状态**，profile 与登录状态不恢复；
- fork 出的新 Session 用 `initializeBrowserFor` 初始化；旧 Session 释放后其工具
  注册一并撤销（同一时刻仅一个 Session 持有浏览器）。

## 工具集与风险分级

工具由 Provider 拥有（Playwright MCP 的典型工具见下表），`browserToolRisk` 做风险
分级，供审批门控读取：

| 风险 | 工具 |
|------|------|
| `low`（只读） | `browser_navigate` / `browser_snapshot` / `browser_wait_for` / `browser_take_screenshot` |
| `medium`（交互） | `browser_click` / `browser_type` / `browser_select_option` / `browser_press_key` |
| `high`（敏感） | `browser_evaluate` / `browser_file_upload` / `browser_download` / 提交表单 |

## Provider

| Provider | 集成方式 | 说明 |
|----------|----------|------|
| `PlaywrightMcpProvider`（默认） | MCP（stdio） | `npx @playwright/mcp`，成熟、多引擎，复用 `conatus_mcp` 客户端 |
| `ChromeDevToolsMcpProvider` | MCP（stdio） | `npx chrome-devtools-mcp`，深度集成 DevTools，只支持 Chromium |
| `StagehandProvider` | 原生（骨架） | 需外部 Stagehand SDK 与其显式配置的原生模型（conatus `llm` 不参与其推理），**暂未接入**，`initializeFor` 抛 `UnsupportedError` |

MCP 类 Provider 支持 `transportFactory` 注入 Mock Server（测试用）；环境变量可写
`${KEY}` 凭据占位符，由 `resolveCredentialPlaceholders` 解析。

## 运行时 seam（全部可选注入）

| seam | 用途 | 缺省行为 |
|------|------|----------|
| `tools` | 注册浏览器工具 | 必需（缺省取 `ctx.tools`） |
| `session` | 浏览器绑定 Session | 不绑定（用 `initializeBrowserFor` 手动初始化） |
| `taskCenter` | 浏览器操作作为 Task（`kind: custom`） | 不追踪 |
| `approval` | 高危操作审批（挂标准 `instrumentApproval`，threshold high） | 自动批准 |
| `telemetry` | 埋点（`browser.provider.registered` / `browser.session.*` / `browser.action.*` / `browser.navigation` / `browser.screenshot`） | 无埋点 |
| `credentials` | MCP Server 环境变量占位符解析 | 无 |

每次操作同时记录为 `browser/action` 会话事件（`parentEventId` 串因果链，符合
「模型可见即已记录」不变式）。

## 注意与限制

- **唯一 Provider**：共享服务只注册一个 Provider，第二个注册（含同名）失败。
- **能力约束**：browser_use 只暴露浏览器操作工具，不暴露通用浏览器资源或模型控制
  的选择器；工具 schema、结果渲染、图像支持由 Provider 拥有。
- **附加模式**：附加的浏览器仍归外部所有，清理只断开连接、不关闭浏览器。
- **语音场景**：语音交互（TTS 播报 / ASR 确认）属于上层装配的一部分，通过
  `approval` seam 组合 `VoiceApproval` 实现，本包不引入 tts / asr 依赖。
- 依赖方向：`conatus_browser_use → conatus_mcp / conatus_agent → conatus_core`，
  反向不成立；`conatus_agent` / `conatus_mcp` 不依赖本包。
- 设计细节见仓库根 `handoff-browser-use.md` 与 `.handoffs/HANDOFF-9.md`。
