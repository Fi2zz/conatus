/// 资源 / prompt 测试共用装配：两台假 server + 可选资源工具注册。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_mcp/conatus_mcp.dart';

import 'mcp_resource_fake.dart';

export 'mcp_resource_fake.dart';

/// 装配 alpha / beta 两台假 server。
///
/// [failingServer] 的 [failingMethods] 回 JSON-RPC 错误（其余照常应答），
/// 用来验证「单台失败不影响其他 server」。
Future<McpRegistry> bootResourceRegistry(
  Context ctx, {
  String? failingServer,
  Set<String> failingMethods = const <String>{},
}) =>
    provideMcp(
      ctx,
      <McpServerConfig>[
        McpServerConfig(
          name: 'alpha',
          type: McpTransportType.stdio,
          command: 'x',
        ),
        McpServerConfig(
          name: 'beta',
          type: McpTransportType.stdio,
          command: 'x',
        ),
      ],
      transportFactory: (McpServerConfig config) => fakeServer(
        config.name,
        failing:
            config.name == failingServer ? failingMethods : const <String>{},
      ),
    );

/// 装配注册表并注册资源工具（供工具用例使用）。
///
/// 不显式传 registry：顺带覆盖 `ctx.require('mcp')` 的默认取服务路径。
Future<McpRegistry> bootToolRegistry(
  Context ctx, {
  String? failingServer,
  Set<String> failingMethods = const <String>{},
}) async {
  final McpRegistry registry = await bootResourceRegistry(
    ctx,
    failingServer: failingServer,
    failingMethods: failingMethods,
  );
  provideMcpResourceTools(ctx);
  return registry;
}
