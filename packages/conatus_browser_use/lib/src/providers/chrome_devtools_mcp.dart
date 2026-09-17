/// Chrome DevTools MCP Provider。
library;

import '../session_browser.dart';
import 'mcp_browser_provider.dart';

/// 通过 `npx chrome-devtools-mcp` 启动的浏览器 Provider。
///
/// 深度集成 Chrome DevTools：网络检查、性能分析、Console 日志。
/// 只支持 Chromium。复用 `conatus_mcp` 客户端。
class ChromeDevToolsMcpProvider extends McpBrowserUseProvider {
  /// 构造。
  ChromeDevToolsMcpProvider({
    super.command = 'npx',
    super.args = const <String>['-y', 'chrome-devtools-mcp@latest'],
    super.env,
    super.config = const BrowserConfig(),
    super.credentials,
    super.transportFactory,
  });

  @override
  String get name => 'chrome-devtools';

  @override
  String get serverName => 'chrome-devtools';
}
