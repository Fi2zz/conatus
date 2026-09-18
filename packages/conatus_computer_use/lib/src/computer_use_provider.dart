/// computer use 装配：提供 `'computerUse'` 服务。
library;

import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:conatus_tasks/conatus_tasks.dart';

import 'desktop.dart';
import 'desktop_action_tool.dart';
import 'provider.dart';
import 'providers/cua_driver_mcp.dart';
import 'registry.dart';

/// 提供 `'computerUse'` 服务。
///
/// 依赖（全部可选，缺省时降级）：
/// - [provider]：桌面 Provider；缺省 [CuaDriverMcpProvider]；
/// - [tools]：注册桌面操作工具；缺省 `ctx.tools`；
/// - [taskCenter]：桌面操作作为 Task；缺省 `ctx.get('tasks')`；
/// - [approval]：高危操作审批；显式提供时挂标准审批中间件（threshold high，
///   拦截**所有输入操作**），缺省不挂（自动批准）——注意若调用方已
///   `provideApproval`，工具的风险等级声明已生效，无需重复传；
/// - [telemetry]：埋点；缺省 `ctx.get('telemetry')`。
///
/// Provider 注册是唯一的：本函数装配时预留槽位；第二个注册（含同名）失败。
/// Provider 的桌面初始化是异步的：启动失败会释放此次尝试的注册（可重试），
/// MCP 重连期间**保留**注册。返回的注册表随 [ctx] 释放自动释放，同时调用
/// [ComputerUseProvider.dispose]。
ComputerUseRegistry provideComputerUse(
  Context ctx, {
  ComputerUseProvider? provider,
  ToolRegistry? tools,
  TaskCenter? taskCenter,
  Approval? approval,
  Telemetry? telemetry,
}) {
  final ComputerUseProvider resolved = provider ?? CuaDriverMcpProvider();
  final ToolRegistry registry = tools ?? ctx.tools;
  final TaskCenter? tasks = taskCenter ?? ctx.get<TaskCenter>('tasks');
  final Telemetry? sink = telemetry ?? ctx.get<Telemetry>('telemetry');

  final ComputerUseRegistryImpl service = ComputerUseRegistryImpl(resolved);
  final Disposer release = service.claim(resolved.name);
  ctx.provide('computerUse', service);
  ctx.onDispose(() {
    release();
    unawaited(resolved.dispose());
  });
  sink?.emit(TelemetryEvent('computer.provider.registered',
      data: <String, Object?>{'provider': resolved.name}));

  if (approval != null) {
    instrumentApproval(ctx, approval: approval, tools: registry);
  }

  unawaited(_bootstrap(
    ctx,
    resolved,
    registry,
    tasks,
    sink,
    release,
  ));
  return service;
}

/// 为上层在知道触发 Session 时注册带会话日志记录的桌面工具。
///
/// computer-use 的桌面操作不属于任何 Session，但可记录到触发它的 Session
/// 日志（handoff-10 6.4）：[sessionId] 是触发 Session 的 id，[sessionLog]
/// 是 `'sessionLog'` 服务或任意实现。重复调用会因工具同名抛 [StateError]，
/// 请先撤销前次注册（ctx 释放或手动 disposer）。
void registerDesktopTools(
  Context ctx,
  DesktopSession desktop, {
  String? sessionId,
  SessionLog? sessionLog,
  ToolRegistry? tools,
  TaskCenter? taskCenter,
  Telemetry? telemetry,
}) {
  final ToolRegistry registry = tools ?? ctx.tools;
  for (final McpTool tool in desktop.tools) {
    ctx.effect(() => registry.register(DesktopActionTool(
          desktop,
          tool,
          sessionId: sessionId,
          sessionLog: sessionLog,
          taskCenter: taskCenter,
          telemetry: telemetry,
        )));
  }
}

/// 异步初始化桌面：成功注册全部工具；启动失败释放此次尝试的注册。
Future<void> _bootstrap(
  Context ctx,
  ComputerUseProvider provider,
  ToolRegistry tools,
  TaskCenter? tasks,
  Telemetry? sink,
  Disposer release,
) async {
  final DesktopSession desktop;
  try {
    desktop = await provider.initialize();
  } catch (_) {
    release();
    sink?.emit(TelemetryEvent('computer.provider.released',
        data: <String, Object?>{
          'provider': provider.name,
          'reason': 'startup-failed',
        }));
    return;
  }
  registerDesktopTools(
    ctx,
    desktop,
    tools: tools,
    taskCenter: tasks,
    telemetry: sink,
  );
}
