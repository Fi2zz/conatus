/// MCP 服务注册表：按 server 名持有客户端与已注册的工具。
library;

import 'dart:async';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'mcp_client.dart';
import 'mcp_prompt_types.dart';
import 'mcp_protocol_tool.dart';
import 'mcp_resource_types.dart';
import 'mcp_tool.dart';

part 'mcp_registry_binding.dart';

/// 已装配的 MCP server 集合，服务键 `'mcp'`（见 `ctx.mcp`）。
///
/// 一台 server 的运行时绑定 = 客户端 + 已注册适配器 + 撤销句柄。断连（服务端
/// 崩溃、连接被掐）时只注销该 server 的工具，其余 server 照常可用——MCP 服务端
/// 是外部进程，随时可能消失，不能让它拖垮整张工具表。
class McpRegistry {
  final Map<String, _McpBinding> _bindings = <String, _McpBinding>{};
  final Map<String, String> _errors = <String, String>{};

  /// 已装配且连接仍活着的 server 名（按装配顺序）。
  List<String> get servers => _bindings.keys.toList(growable: false);

  /// 按 server 记录最近一次目录请求失败原因（成功一次即清除），供工具层在
  /// 聚合结果为空时给出可诊断提示。
  Map<String, String> get lastErrors =>
      Map<String, String>.unmodifiable(_errors);

  /// 某 server 最近一次失败原因；没有失败返回 `null`。
  String? lastErrorFor(String server) => _errors[server];

  /// 某 server 的客户端；未装配（或已断连注销）返回 `null`。
  McpClient? clientOf(String serverName) => _bindings[serverName]?.client;

  /// 某 server 当前注册的适配器（不含别名工具）。
  List<McpToolAdapter> toolsOf(String serverName) =>
      List<McpToolAdapter>.unmodifiable(
        _bindings[serverName]?.tools ?? const <McpToolAdapter>[],
      );

  /// 装配一台 server：握手、发现工具、注册进 `ctx.tools`，并订阅其断连。
  ///
  /// 失败时先断开该客户端再抛出（不留悬空子进程），且不上账；同名重复装配抛
  /// [StateError]。
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

  /// 列出资源；[server] 为空时汇总全部 server。
  ///
  /// 只查询握手时声明了 `resources` 能力的 server；单台请求失败按空表处理
  /// （原因进 [lastErrors]），不打断其他 server。
  Future<List<McpResource>> listResources({String? server}) => _collect(
        server,
        (McpClient client) => client.listResources(),
        supported: _supportsResources,
      );

  /// 读取一个资源；server 未知、未声明资源能力或读取失败返回空表。
  Future<List<McpResourceContents>> readResource({
    required String server,
    required String uri,
  }) =>
      _collect(
        server,
        (McpClient client) => client.readResource(uri),
        supported: _supportsResources,
      );

  /// 列出提示词模板；[server] 为空时汇总全部 server。
  Future<List<McpPrompt>> listPrompts({String? server}) => _collect(
        server,
        (McpClient client) => client.listPrompts(),
        supported: _supportsPrompts,
      );

  /// 取一条提示词并填参；server 未知、未声明能力或取值失败返回空表。
  Future<List<McpPromptMessage>> getPrompt({
    required String server,
    required String name,
    Map<String, String> arguments = const <String, String>{},
  }) =>
      _collect(
        server,
        (McpClient client) => client.getPrompt(name, arguments: arguments),
        supported: _supportsPrompts,
      );

  /// 逐台取目录；单台失败只记原因并跳过，成功一次即清除该 server 的旧错误。
  Future<List<T>> _collect<T>(
    String? server,
    Future<List<T>> Function(McpClient client) fetch, {
    bool Function(McpClient client)? supported,
  }) async {
    final List<T> items = <T>[];
    for (final _McpBinding binding in _targets(server)) {
      final McpClient client = binding.client;
      if (supported != null && !supported(client)) continue;
      try {
        items.addAll(await fetch(client));
        _errors.remove(client.serverName);
      } on Object catch (error) {
        _errors[client.serverName] = '$error';
      }
    }
    return items;
  }

  List<_McpBinding> _targets(String? server) {
    if (server == null) return _bindings.values.toList(growable: false);
    final _McpBinding? binding = _bindings[server];
    return binding == null ? <_McpBinding>[] : <_McpBinding>[binding];
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
    _errors.clear();
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
    _errors.remove(serverName);
  }
}

bool _supportsResources(McpClient client) =>
    client.serverInfo?.capabilities.resources ?? false;

bool _supportsPrompts(McpClient client) =>
    client.serverInfo?.capabilities.prompts ?? false;
