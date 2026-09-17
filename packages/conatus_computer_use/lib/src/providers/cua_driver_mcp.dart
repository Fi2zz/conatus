/// Cua Driver MCP Provider（默认）：复用 `conatus_mcp` 客户端。
library;

import 'dart:async';

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_mcp/conatus_mcp.dart';

import '../desktop.dart';
import '../image_routing.dart';
import '../provider.dart';
import '../screenshot.dart';

/// 通过 `cua-driver mcp` 启动的桌面 Provider（stdio 传输）。
///
/// 生命周期（handoff-10 7.4）：
///
/// - `initialize()` 成功 → 保留注册（注册槽位由装配层管理）；
/// - 启动失败 → 装配层释放此次尝试的注册（可重新尝试）；
/// - MCP 断连 → **保留注册**（暂时性故障），断连标记后重连（再次
///   `initialize()`）会重建客户端；
/// - `dispose()` → 先停工具（关闭会话），再释放客户端。
///
/// 截图：`capture` 调 MCP `screenshot` 工具并提取图像块；挂载
/// [attachmentStore] 且 [imageSupport] 为 [ImageSupport.persistent] 时
/// 持久化并回填 `attachmentRef`，否则原样返回。
class CuaDriverMcpProvider implements ComputerUseProvider {
  /// 构造。
  CuaDriverMcpProvider({
    this.command = 'cua-driver',
    this.args = const <String>['mcp'],
    this.env,
    this.timeout = const Duration(seconds: 30),
    this.attachmentStore,
    this.imageSupport = ImageSupport.diagnostic,
    this.transportFactory,
  });

  /// 可执行文件。
  final String command;

  /// 命令行参数。
  final List<String> args;

  /// 注入子进程的环境变量。
  final Map<String, String>? env;

  /// 单次请求超时。
  final Duration timeout;

  /// 附件存储（持久化截图；可选）。
  final AttachmentStore? attachmentStore;

  /// 图像支持级别（模型路由结果；缺省诊断）。
  final ImageSupport imageSupport;

  /// 传输工厂（测试注入 Mock Server 用）。缺省按参数造 [StdioTransport]。
  final McpTransport Function(
    String command,
    List<String> args,
    Map<String, String> env,
  )? transportFactory;

  McpClient? _client;
  _CuaDriverDesktopSession? _session;
  StreamSubscription<void>? _disconnects;

  @override
  String get name => 'cua-driver-mcp';

  @override
  Future<DesktopSession> initialize() async {
    final _CuaDriverDesktopSession? existing = _session;
    if (existing != null) return existing;

    final McpClient client = McpClient(
      transport: transportFactory != null
          ? transportFactory!(command, args, env ?? const <String, String>{})
          : StdioTransport(
              command: command,
              args: args,
              env: env ?? const <String, String>{},
            ),
      serverName: 'cua-driver',
      timeout: timeout,
    );
    try {
      await client.initialize();
      final List<String> toolNames =
          (await client.listTools()).map((McpTool tool) => tool.name).toList();
      _client = client;
      _session = _CuaDriverDesktopSession(
        client: client,
        toolNames: toolNames,
        attachmentStore: attachmentStore,
        imageSupport: imageSupport,
      );
      _watchDisconnects(client);
      return _session!;
    } catch (_) {
      await client.close();
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    await _disconnects?.cancel();
    _disconnects = null;
    await _session?.close();
    _session = null;
    await _client?.close();
    _client = null;
  }

  /// 断连标记：保留注册（装配层不释放），等待重连。
  void _watchDisconnects(McpClient client) {
    _disconnects?.cancel();
    _disconnects = client.disconnects.listen((_) {
      _session = null;
    });
  }
}

/// 绑定的桌面会话（不绑定任何 Session）。
class _CuaDriverDesktopSession implements DesktopSession {
  _CuaDriverDesktopSession({
    required this.client,
    required this.toolNames,
    this.attachmentStore,
    this.imageSupport = ImageSupport.diagnostic,
  });

  /// 底层 MCP 客户端（生命周期由 Provider 管理）。
  final McpClient client;

  @override
  final List<String> toolNames;

  /// 附件存储（持久化截图；可选）。
  final AttachmentStore? attachmentStore;

  /// 图像支持级别。
  final ImageSupport imageSupport;

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
  Future<Screenshot> capture({ScreenRegion? region}) async {
    final McpToolResult raw = await client.callTool('screenshot', <String, Object?>{
      if (region != null) 'region': region.toJson(),
    });
    final List<int> bytes = _extractBytes(raw);
    final Screenshot screenshot = Screenshot(
      bytes: bytes,
      width: _intOf(raw.structuredContent?['width']) ?? 0,
      height: _intOf(raw.structuredContent?['height']) ?? 0,
      capturedAt: DateTime.now(),
    );
    final AttachmentStore? store = attachmentStore;
    if (imageSupport == ImageSupport.persistent &&
        store != null &&
        !screenshot.isEmpty) {
      final String ref = await store.save(bytes, mimeType: screenshot.mimeType);
      return screenshot.copyWith(attachmentRef: ref);
    }
    return screenshot;
  }

  @override
  Future<void> close() async {}
}

List<int> _extractBytes(McpToolResult raw) {
  for (final McpContent block in raw.content) {
    if (block.type == 'image' && block.data is String) {
      return decodeBase64Bytes(block.data as String);
    }
  }
  final Object? data = raw.structuredContent?['data'];
  if (data is String) return decodeBase64Bytes(data);
  return const <int>[];
}

int? _intOf(Object? value) => value is int ? value : null;
