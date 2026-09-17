/// Playwright MCP Provider（默认）。
library;

import '../session_browser.dart';
import 'mcp_browser_provider.dart';

/// 通过 `npx @playwright/mcp` 启动的浏览器 Provider。
///
/// 支持的浏览器引擎：Chromium（默认）、Firefox、WebKit。需要 Node.js。
/// 复用 `conatus_mcp` 客户端：每个 Session 一个 [McpClient]，
/// 跨轮次复用，Session 释放时关闭其浏览器。
class PlaywrightMcpProvider extends McpBrowserUseProvider {
  /// 构造。
  PlaywrightMcpProvider({
    super.command = 'npx',
    super.args = const <String>['-y', '@playwright/mcp@latest'],
    super.env,
    super.config = const BrowserConfig(),
    super.credentials,
    super.transportFactory,
  });

  @override
  String get name => 'playwright';

  @override
  String get serverName => 'playwright';
}
