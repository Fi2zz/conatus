/// conatus_computer_use：计算机操作（实验性）。
///
/// 本包处于早期探索阶段，API 可能在没有 major 版本号变更的情况下发生
/// 破坏性改动。请勿在生产环境依赖它。
///
/// 桌面操作通过 [ComputerUseRegistry]（共享服务，只注册一个 Provider）与
/// [ComputerUseProvider]（Cua Driver MCP / 原生）提供。与 browser-use 的
/// 关键区别：computer-use **没有 Session 级别的桌面所有权**——桌面是共享
/// 资源，Provider 不为某个 Session 预留桌面，调用方负责协调跨 Session 的
/// 完整观察、操作与验证流程。取消调用**无法撤销**桌面已收到的输入。
///
/// 与现有组件的协同（全部为可选 seam，缺省降级）：
///
/// - `mcp`：首选 Provider（Cua Driver MCP）通过 [McpClient] 连接；
/// - `tools`：桌面操作注册为 `Tool`（[DesktopActionTool]）；
/// - `tasks`：每次操作追踪为 `Task(kind: custom)`；
/// - `approval`：**所有输入操作都是 high 风险**，走 [Approval] 审批
///   （复用 `instrumentApproval` 标准中间件）；
/// - `sessionLog`：操作记录到触发它的 Session 日志（不绑定任何 Session）；
/// - `telemetry`：`computer.*` 事件埋点；
/// - `attachmentStore`：持久化截图（支持图像的模型路由接收持久化截图，
///   不支持的接收 MCP 图像诊断，见 [ImageSupport]）。
///
/// **语音场景适配**：智能音箱场景下用户看不到屏幕，每一步操作都要口头
/// 描述、高危操作必须走审批、完成后要有明确验证。语音交互属于上层装配
/// 的一部分，通过 `approval` seam 组合 `VoiceApproval` 实现，本包不引入
/// tts / asr 依赖。
library;

export 'src/computer_use_provider.dart'
    show provideComputerUse, registerDesktopTools;
export 'src/desktop.dart' show DesktopSession;
export 'src/desktop_action_tool.dart'
    show DesktopActionTool, desktopToolRisk;
export 'src/image_routing.dart' show ImageSupport, imageSupportFor;
export 'src/provider.dart' show ComputerUseProvider;
export 'src/providers/cua_driver_mcp.dart' show CuaDriverMcpProvider;
export 'src/providers/cua_driver_native.dart' show CuaDriverNativeProvider;
export 'src/registry.dart'
    show ComputerUseProviderName, ComputerUseRegistry, ComputerUseRegistryImpl;
export 'src/screenshot.dart'
    show
        AttachmentStore,
        InMemoryAttachmentStore,
        ScreenRegion,
        Screenshot,
        decodeBase64Bytes,
        encodeBase64Bytes;
