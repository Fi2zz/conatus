/// 基于 stdio MCP 的浏览器 Provider 共享实现（Playwright / Chrome DevTools）。
library;

import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_mcp/conatus_mcp.dart';

import '../provider.dart';
import '../session_browser.dart';

/// 经 stdio 传输连接 MCP server 的浏览器 Provider。
///
/// 每个 Session 一个 [McpClient]：跨轮次复用（按 sessionId 持有），
/// 释放时关闭该 Session 的浏览器与客户端。`PLAYWRIGHT_HEADLESS` /
/// `PLAYWRIGHT_PROFILE` 等浏览器环境经 [env] 注入子进程；
/// `${KEY}` 凭据占位符由 [resolveCredentialPlaceholders] 解析。
abstract class McpBrowserUseProvider implements BrowserUseProvider {
  /// 构造。[command] / [args] / [env] 决定启动的 MCP server。
  McpBrowserUseProvider({
    this.command = 'npx',
    this.args = const <String>[],
    this.env,
    this.config = const BrowserConfig(),
    this.credentials,
    this.transportFactory,
  });

  /// 可执行文件。
  final String command;

  /// 命令行参数。
  final List<String> args;

  /// 注入子进程的环境变量（可用 `${KEY}` 凭据占位符）。
  final Map<String, String>? env;

  /// 浏览器配置。
  final BrowserConfig config;

  /// 凭据（解析环境变量占位符）。
  final Credentials? credentials;

  /// 传输工厂（测试注入 Mock Server 用）。缺省按参数造 [StdioTransport]。
  final McpTransport Function(
    String command,
    List<String> args,
    Map<String, String> env,
  )? transportFactory;

  /// MCP server 名（工具名前缀与日志归因）。
  String get serverName;

  final Map<String, McpClient> _clients = <String, McpClient>{};
  final Map<String, SessionBrowser> _browsers = <String, SessionBrowser>{};

  @override
  Future<SessionBrowser> initializeFor(Session session) async {
    final SessionBrowser? existing = _browsers[session.id];
    if (existing != null) return existing;

    final Map<String, String> env = _envWithConfig();
    final McpClient client = McpClient(
      transport: transportFactory != null
          ? transportFactory!(command, args, env)
          : StdioTransport(
              command: command,
              args: args,
              env: resolveCredentialPlaceholders(env, credentials),
            ),
      serverName: serverName,
    );
    try {
      await client.initialize();
      final List<String> toolNames =
          (await client.listTools()).map((McpTool tool) => tool.name).toList();
      final SessionBrowser browser = _McpSessionBrowser(
        sessionId: session.id,
        client: client,
        toolNames: toolNames,
      );
      _clients[session.id] = client;
      _browsers[session.id] = browser;
      return browser;
    } catch (_) {
      await client.close();
      rethrow;
    }
  }

  @override
  Future<void> release(Session session) async {
    final SessionBrowser? browser = _browsers.remove(session.id);
    if (browser != null) await browser.close();
    final McpClient? client = _clients.remove(session.id);
    if (client != null) await client.close();
  }

  @override
  Future<void> dispose() async {
    final List<SessionBrowser> browsers = _browsers.values.toList();
    final List<McpClient> clients = _clients.values.toList();
    _browsers.clear();
    _clients.clear();
    for (final SessionBrowser browser in browsers) {
      await browser.close();
    }
    for (final McpClient client in clients) {
      await client.close();
    }
  }

  Map<String, String> _envWithConfig() => <String, String>{
        ...?env,
        'PLAYWRIGHT_HEADLESS': '${config.headless}',
        if (config.profile != null) 'PLAYWRIGHT_PROFILE': config.profile!,
      };
}

/// 绑定一个 Session 的 MCP 浏览器。
class _McpSessionBrowser implements SessionBrowser {
  _McpSessionBrowser({
    required this.sessionId,
    required this.client,
    required this.toolNames,
  });

  @override
  final String sessionId;

  /// 底层 MCP 客户端（生命周期由 Provider 管理）。
  final McpClient client;

  @override
  final List<String> toolNames;

  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  Future<ToolResult> call(String toolName, Map<String, Object?> args) async {
    try {
      return toolResultFromMcp(await client.callTool(toolName, args));
    } on McpException catch (error) {
      return ToolResult.failure(
        error.message,
        error: ToolError('MCP_ERROR', error.message),
      );
    }
  }

  @override
  Future<void> close() async {
    _active = false;
  }
}
