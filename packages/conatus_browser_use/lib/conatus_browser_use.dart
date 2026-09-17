/// conatus_browser_use：浏览器操作（实验性）。
///
/// 本包处于早期探索阶段，API 可能在没有 major 版本号变更的情况下发生
/// 破坏性改动。请勿在生产环境依赖它。
///
/// 浏览器操作通过 [BrowserUseRegistry]（共享服务，只注册一个 Provider）与
/// [BrowserUseProvider]（Playwright / Chrome DevTools / Stagehand）提供：
/// 启动的浏览器绑定使用它的 Session，跨轮次复用；Session 释放时关闭其
/// 启动的资源；重新加载或 fork Session 时创建**全新浏览器状态**。
///
/// 与现有组件的协同（全部为可选 seam，缺省降级）：
///
/// - `mcp`：首选 Provider 通过 [McpClient] 连接（Playwright / Chrome DevTools）；
/// - `session`：浏览器绑定 Session（[provideBrowserUse] 的 `session` 参数），
///   或 fork 出新 Session 后调 [initializeBrowserFor]；
/// - `tools`：浏览器操作注册为 `Tool`（[BrowserActionTool]）；
/// - `tasks`：每次操作追踪为 `Task(kind: custom)`；
/// - `approval`：高危操作（执行 JS / 上传 / 下载 / 提交表单）经
///   [Approval] 审批（复用 `instrumentApproval` 标准中间件）；
/// - `telemetry`：`browser.*` 事件埋点。
///
/// **语音场景适配**：语音交互（TTS 播报 / ASR 确认）属于上层装配的一部分，
/// 通过 `approval` seam 组合 `VoiceApproval` 实现，本包不引入 tts / asr 依赖。
library;

export 'src/browser_action_tool.dart' show BrowserActionTool;
export 'src/browser_tool_risk.dart' show browserToolRisk;
export 'src/browser_use_provider.dart'
    show initializeBrowserFor, provideBrowserUse;
export 'src/provider.dart' show BrowserUseProvider;
export 'src/providers/chrome_devtools_mcp.dart'
    show ChromeDevToolsMcpProvider;
export 'src/providers/playwright_mcp.dart' show PlaywrightMcpProvider;
export 'src/providers/stagehand.dart' show StagehandProvider;
export 'src/registry.dart'
    show BrowserUseProviderName, BrowserUseRegistry, BrowserUseRegistryImpl;
export 'src/session_browser.dart'
    show BrowserConfig, BrowserLaunchMode, SessionBrowser;
