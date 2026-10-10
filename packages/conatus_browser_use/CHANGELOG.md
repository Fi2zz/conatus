# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

初始实现——浏览器操作能力缝，让模型经配置的 Provider 检查与操作网页：

- `BrowserUseRegistry`（服务键 `'browserUse'`）+ `provideBrowserUse`：
  单 Provider 注册（第二个注册失败），`SessionBrowser` 绑定 Session 跨轮次
  复用，Session 释放时关闭其启动的资源
- `BrowserUseProvider` seam：`PlaywrightMcpProvider`（MCP stdio，多引擎）/
  `ChromeDevToolsMcpProvider`（MCP stdio，仅 Chromium）/ `StagehandProvider`
  （骨架，暂未接入）；`transportFactory` 支持注入 Mock Server
- `BrowserConfig`：`launch` / `attach` 启动模式、`headless`（默认 true）、
  `profile` / `viewport` / `userAgent`
- 工具集由 Provider 拥有（`browser_navigate` / `browser_click` /
  `browser_type` / `browser_evaluate` 等），`browserToolRisk` 三级风险分级
  供审批门控；高危操作经 `approval` seam 走审批（缺省自动批准）
- fork / 重载 Session 创建全新浏览器状态（登录状态不从会话日志恢复），
  `initializeBrowserFor` 手动初始化
- 埋点（`browser.*`）与 `browser/action` 会话事件（`parentEventId`
  串因果链，符合「模型可见即已记录」不变式）
