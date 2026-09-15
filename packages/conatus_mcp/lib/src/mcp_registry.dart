/// MCP 服务注册表：按 server 名持有客户端与已注册的工具。
library;

import 'dart:async';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'mcp_client.dart';
import 'mcp_protocol_tool.dart';
import 'mcp_tool.dart';

/// 已装配的 MCP server 集合，服务键 `'mcp'`（见 `ctx.mcp`）。
///
/// 一台 server 的运行时绑定 = 客户端 + 已注册适配器 + 撤销句柄。断连（服务端
/// 崩溃、连接被掐）时只注销该 server 的工具，其余 server 照常可用——MCP 服务端
/// 是外部进程，随时可能消失，不能让它拖垮整张工具表。
class McpRegistry {
  final Map<String, _McpBinding> _bindings = <String, _McpBinding>{};

  /// 已装配且连接仍活着的 server 名（按装配顺序）。
  List<String> get servers => _bindings.keys.toList(growable: false);

  /// 某 server 的客户端；未装配（或已断连注销）返回 `null`。
  McpClient? clientOf(String serverName) => _bindings[serverName]?.client;

  /// 某 server 当前注册的适配器（不含别名工具）。
  List<McpToolAdapter> toolsOf(String serverName) =>
      List<McpToolAdapter>.unmodifiable(
        _bindings[serverName]?.tools ?? const <McpToolAdapter>[],
      );

  /// 装配一台 server：握手、发现工具、注册进 `ctx.tools`，并订阅其断连。
  ///
  /// 握手或发现失败时先断开该客户端再抛出（不留悬空子进程），且不上账，
  /// 因此 `servers` 里不会留下半死条目。同名 server 重复装配抛 [StateError]。
  Future<void> attach(Context ctx, McpClient client) async {
    final String name = client.serverName;
    if (_bindings.containsKey(name)) {
      throw StateError('MCP server "$name" 已装配');
    }
    try {
      await client.initialize();
      final List<McpTool> tools = await client.listTools();
      final _McpBinding binding = _McpBinding(client);
      _bindings[name] = binding;
      for (final McpTool tool in tools) {
        binding.add(ctx, McpToolAdapter(client: client, tool: tool));
      }
      binding.watchDisconnect(ctx, () => _drop(name));
    } catch (error) {
      _bindings.remove(name);
      await client.close();
      rethrow;
    }
  }

  /// 给已注册的全名工具登记一个短别名（如 `read_file` → `fs__read_file`）。
  ///
  /// 目标工具不存在抛 [StateError]；短名与已有工具撞车由
  /// [ToolRegistry.register] 抛 [StateError]。
  void addAlias(Context ctx, String alias, String fullName) {
    final _McpBinding? binding = _bindingWith(fullName);
    if (binding == null) {
      throw StateError('别名 "$alias" 的目标工具 "$fullName" 未注册');
    }
    binding.add(
        ctx, McpToolAlias(inner: binding.require(fullName), alias: alias));
  }

  /// 断开全部连接并注销全部工具；幂等。
  Future<void> close() async {
    final List<_McpBinding> bindings = _bindings.values.toList(growable: false);
    _bindings.clear();
    for (final _McpBinding binding in bindings) {
      await binding.close();
    }
  }

  _McpBinding? _bindingWith(String fullName) {
    for (final _McpBinding binding in _bindings.values) {
      if (binding.holds(fullName)) return binding;
    }
    return null;
  }

  void _drop(String serverName) {
    _bindings.remove(serverName);
  }
}

/// 一台 server 的运行时绑定：客户端、已注册工具与撤销句柄。
class _McpBinding {
  _McpBinding(this.client);

  final McpClient client;
  final List<McpToolAdapter> tools = <McpToolAdapter>[];
  final List<Disposer> _disposers = <Disposer>[];
  StreamSubscription<void>? _disconnects;

  /// 注册一个工具（含别名）并记住撤销句柄；`ctx` 释放时也会撤销（幂等）。
  void add(Context ctx, Tool tool) {
    final Disposer off = ctx.tools.register(tool);
    _disposers.add(off);
    ctx.onDispose(off);
    if (tool is McpToolAdapter) tools.add(tool);
  }

  /// 该绑定是否持有全名为 [fullName] 的适配器。
  bool holds(String fullName) =>
      tools.any((McpToolAdapter tool) => tool.name == fullName);

  /// 按全名取适配器；不存在抛 [StateError]。
  McpToolAdapter require(String fullName) =>
      tools.firstWhere((McpToolAdapter tool) => tool.name == fullName);

  /// 订阅客户端断连：注销本 server 的工具后回调 [onGone]。
  void watchDisconnect(Context ctx, void Function() onGone) {
    _disconnects = client.disconnects.listen((_) {
      detachTools();
      onGone();
    });
    ctx.onDispose(() => unawaited(_disconnects?.cancel()));
  }

  /// 注销本 server 注册的全部工具。
  void detachTools() {
    for (final Disposer off in _disposers) {
      off();
    }
    _disposers.clear();
    tools.clear();
  }

  /// 断开客户端并注销工具。
  Future<void> close() async {
    await _disconnects?.cancel();
    _disconnects = null;
    detachTools();
    await client.close();
  }
}
