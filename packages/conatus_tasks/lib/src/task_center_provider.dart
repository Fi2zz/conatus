/// task 插件的装配。
///
/// [provideTaskCenter] 提供 `'tasks'` 服务并注册 `list_tasks` /
/// `cancel_task` 工具；[provideTaskTracking] 把运行时接入挂好：
/// `spawn_agent` 中间件注册到工具管线，`agentLoop` 可用时经 `ctx.inject`
/// 把轮次追踪器挂到 [AgentLoop.turnTracker]（依赖消失自动摘除，与
/// `provideGoal` 挂载续行驱动器同款）。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'task_center.dart';
import 'task_center_default.dart';
import 'task_tools.dart';
import 'task_tracking.dart';

/// 提供 `'tasks'` 服务并注册任务工具。
///
/// 依赖（全部可选，缺省时降级）：`session` 持久化 `task/changed` 事件、
/// `approval` shell 类任务取消确认（缺省自动批准）、`telemetry` 埋点；
/// `tools` 缺省取 `ctx.tools`。[registerTools] 关闭时不注册模型工具。
TaskCenter provideTaskCenter(
  Context ctx, {
  TaskCenter? taskCenter,
  Session? session,
  Approval? approval,
  Telemetry? telemetry,
  ToolRegistry? tools,
  bool registerTools = true,
}) {
  final TaskCenter resolved = taskCenter ??
      DefaultTaskCenter(
        session: session,
        approval: approval,
        telemetry: telemetry,
        ctx: ctx,
      );
  final ToolRegistry registry = tools ?? ctx.tools;
  ctx.provide('tasks', resolved);
  if (registerTools) {
    ctx.effect(() => registry.register(ListTasksTool(taskCenter: resolved)));
    ctx.effect(() => registry.register(CancelTaskTool(taskCenter: resolved)));
  }
  ctx.onDispose(resolved.dispose);
  return resolved;
}

/// 挂载运行时追踪：`spawn_agent` 中间件 + Agent Loop 轮次钩子。
///
/// [tasks] 缺省取 `ctx.tasks`；[registry] 缺省取 `ctx.tools`。
/// `agentLoop` 尚不可用时经 [Context.inject] 等待，依赖齐备即挂载、
/// 消失即摘除。
TaskTracking provideTaskTracking(
  Context ctx, {
  TaskCenter? tasks,
  ToolRegistry? registry,
}) {
  final TaskCenter resolved = tasks ?? ctx.tasks;
  final ToolRegistry target = registry ?? ctx.tools;
  final TaskTracking tracking = TaskTracking(tasks: resolved, ctx: ctx);
  ctx.effect(() => target.use(tracking.spawnAgentMiddleware));
  ctx.inject(<String>['agentLoop'], (Context child) {
    final AgentLoop agent = child.require<AgentLoop>('agentLoop');
    agent.turnTracker = tracking;
    child.onDispose(() {
      if (identical(agent.turnTracker, tracking)) agent.turnTracker = null;
    });
  });
  return tracking;
}
