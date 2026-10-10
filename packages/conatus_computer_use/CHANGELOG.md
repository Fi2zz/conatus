# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

初始实现——桌面操作能力缝，让模型经配置的 Provider 观察并操作本地桌面：

- `ComputerUseRegistry`（服务键 `'computerUse'`）+ `provideComputerUse`：
  单 Provider 注册（第二个注册失败），与 browser_use 不同——桌面是共享
  资源，`DesktopSession` 不绑定 Session，跨 Session 协调由调用方负责
- `CuaDriverMcpProvider`（MCP stdio，复用 `conatus_mcp` 客户端）/
  `CuaDriverNativeProvider`（骨架，暂未接入）；MCP Provider 支持
  `transportFactory` 注入 Mock Server，`timeout` 默认 30s
- 桌面工具（`screen_capture` / `mouse_click` / `keyboard_type` / `scroll` 等）
  schema 透传给模型；所有输入操作一律 `high` 风险走审批（桌面输入不可撤销，
  无法像浏览器那样区分 medium）
- 图像路由：支持图像的模型接收持久化截图（`AttachmentStore` /
  `InMemoryAttachmentStore`），不支持的接收 MCP 图像诊断文本
- `launch_app` 成功后自动 `bring_to_front` 带到前台（`activateLaunchedApp:
  false` 可关闭，供后台驱动场景）
- 生命周期：初始化失败释放注册可重试；MCP 断连保留注册、再次 `initialize`
  重建客户端；`registerDesktopTools` 可把操作记录进触发它的 Session 日志
