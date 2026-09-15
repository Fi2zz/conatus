/// MCP 装配：从配置连起全部 server，并把它们的工具接进 `ctx.tools`。
///
/// 服务键 `'mcp'`。装配是异步的（要握手与发现工具），因此
/// [provideMcp] 返回 `Future<McpRegistry>`：
///
/// ```dart
/// provideTools(app);
/// await provideMcp(app, <McpServerConfig>[
///   McpServerConfig(
///     name: 'fs',
///     type: McpTransportType.stdio,
///     command: 'npx',
///     args: <String>['-y', '@modelcontextprotocol/server-filesystem', '/tmp'],
///   ),
///   McpServerConfig(
///     name: 'remote',
///     type: McpTransportType.http,
///     url: 'https://mcp.example.com/mcp',
///     headers: <String, String>{'Authorization': r'Bearer ${REMOTE_TOKEN}'},
///   ),
/// ]);
/// ```
library;

import 'dart:async';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_credentials/conatus_credentials.dart';
import 'mcp_client.dart';
import 'mcp_registry.dart';
import 'mcp_transport.dart';
import 'mcp_transport_http.dart';
import 'mcp_transport_sse.dart';
import 'mcp_transport_stdio.dart';
import 'mcp_types.dart';

/// `ctx.mcp`：当前上下文可见的 MCP 注册表。
extension McpContext on Context {
  /// 取当前上下文可见的 [McpRegistry]（未提供时抛 [StateError]）。
  McpRegistry get mcp => require<McpRegistry>('mcp');
}

/// 装配 MCP：逐个 server 建传输、握手、发现工具并注册进 `ctx.tools`。
///
/// 随上下文释放自动断开全部连接并注销工具（见 [McpRegistry.close]）。
///
/// [aliases] 是「短名 → 已注册全名」的映射，如
/// `{'read_file': 'fs__read_file'}`；目标工具不存在时抛 [StateError]。
///
/// [credentials] 用于解析 [McpServerConfig.env] / [McpServerConfig.headers]
/// 里的 `${KEY}` 占位符；缺省时占位符原样保留（见
/// [resolveCredentialPlaceholders]）。
///
/// [transportFactory] 用于测试与自定义传输：给出时由它按配置造传输，缺省按
/// [McpServerConfig.type] 分派到 [StdioTransport] / [HttpTransport] /
/// [SseTransport]。它收到的配置已做过凭据占位符解析。
Future<McpRegistry> provideMcp(
  Context ctx,
  List<McpServerConfig> servers, {
  Map<String, String> aliases = const <String, String>{},
  Credentials? credentials,
  McpTransport Function(McpServerConfig config)? transportFactory,
}) async {
  final McpRegistry registry = McpRegistry();
  ctx.provide('mcp', registry);
  ctx.onDispose(() => unawaited(registry.close()));
  for (final McpServerConfig config in servers) {
    await registry.attach(
      ctx,
      _clientFor(config, credentials, transportFactory),
    );
  }
  for (final MapEntry<String, String> entry in aliases.entries) {
    registry.addAlias(ctx, entry.key, entry.value);
  }
  return registry;
}

/// 按 [config] 造一个客户端（含 `${KEY}` 占位符解析与传输分派）。
///
/// [transport] 给出时由它造传输（测试或自定义传输用），否则按
/// [McpServerConfig.type] 分派。
McpClient _clientFor(
  McpServerConfig config,
  Credentials? credentials,
  McpTransport Function(McpServerConfig config)? transport,
) {
  final McpServerConfig resolved = _resolved(config, credentials);
  return McpClient(
    transport: transport == null ? _transport(resolved) : transport(resolved),
    serverName: resolved.name,
  );
}

/// 把值里的 `${KEY}` 占位符替换成凭据服务里的同名凭据。
///
/// 解析不了（[credentials] 为 `null`、键不存在或取凭据时抛错）的占位符**原样
/// 保留**：不抛错、不写日志、不打印明文。
///
/// **返回值可能含明文凭据**：调用方不得把它写进日志、事件、会话记录或任何模型
/// 可见的字段。
Map<String, String> resolveCredentialPlaceholders(
  Map<String, String> raw,
  Credentials? credentials,
) =>
    <String, String>{
      for (final MapEntry<String, String> entry in raw.entries)
        entry.key: _resolvePlaceholders(entry.value, credentials),
    };

McpServerConfig _resolved(McpServerConfig config, Credentials? credentials) {
  if (credentials == null) return config;
  return config.copyWith(
    env: resolveCredentialPlaceholders(config.env, credentials),
    headers: resolveCredentialPlaceholders(config.headers, credentials),
  );
}

McpTransport _transport(McpServerConfig config) {
  switch (config.type) {
    case McpTransportType.stdio:
      return StdioTransport(
        command: config.command!,
        args: config.args,
        env: config.env,
      );
    case McpTransportType.http:
      return HttpTransport(url: config.url!, headers: config.headers);
    case McpTransportType.sse:
      return SseTransport(url: config.url!, headers: config.headers);
  }
}

String _resolvePlaceholders(String value, Credentials? credentials) {
  if (credentials == null) return value;
  return value.replaceAllMapped(
    _placeholder,
    (Match match) => _credentialValue(match, credentials),
  );
}

String _credentialValue(Match match, Credentials credentials) {
  try {
    return credentials.get(match.group(1)!)?.value ?? match.group(0)!;
  } on Object {
    return match.group(0)!;
  }
}

final RegExp _placeholder = RegExp(r'\$\{([A-Za-z0-9_]+)\}');
