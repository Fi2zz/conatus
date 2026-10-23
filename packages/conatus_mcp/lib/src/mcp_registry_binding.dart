part of 'mcp_registry.dart';

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
