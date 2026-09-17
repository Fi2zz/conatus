/// Workflow 插件入口：装配引擎并注册为 `'workflow'` 服务。
///
/// [provideWorkflow] 依赖 `team` / `tools`（缺省取 `ctx.team` /
/// `ctx.tools`），其余 seam（[taskCenter] / [session] / [approval] /
/// [telemetry]）可选，缺省 no-op。引擎随 [ctx] 释放自动 dispose。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_tasks/conatus_tasks.dart';
import 'package:conatus_team/conatus_team.dart';

import 'engine.dart';
import 'engine_impl.dart';
import 'executor.dart';
import 'hooks.dart';
import 'store.dart';

/// `ctx.workflow`：当前上下文可见的 [WorkflowEngine]。
extension WorkflowContext on Context {
  /// 取当前上下文可见的 [WorkflowEngine]（未提供时抛 [StateError]）。
  WorkflowEngine get workflow => require<WorkflowEngine>('workflow');
}

/// 把 [WorkflowEngine] 作为 `'workflow'` 服务提供到上下文。
///
/// 未传 [engine] 时构建默认实现：节点执行经 [buildNodeExecutor] 接到
/// `team` / `tools`，运行时 seam 经 [WorkflowHooks] 注入。
WorkflowEngine provideWorkflow(
  Context ctx, {
  WorkflowEngine? engine,
  WorkflowStore? store,
  AgentTeam? team,
  ToolRegistry? tools,
  TaskCenter? taskCenter,
  Session? session,
  Approval? approval,
  Telemetry? telemetry,
  int maxDepth = 5,
}) {
  final AgentTeam resolvedTeam = team ?? ctx.team;
  final ToolRegistry resolvedTools = tools ?? ctx.tools;
  final WorkflowEngine resolved = engine ??
      _buildEngine(
        ctx,
        store: store,
        team: resolvedTeam,
        tools: resolvedTools,
        taskCenter: taskCenter,
        session: session,
        approval: approval,
        telemetry: telemetry,
        maxDepth: maxDepth,
      );
  ctx.onDispose(resolved.dispose);
  ctx.provide('workflow', resolved);
  return resolved;
}

WorkflowEngine _buildEngine(
  Context ctx, {
  WorkflowStore? store,
  required AgentTeam team,
  required ToolRegistry tools,
  TaskCenter? taskCenter,
  Session? session,
  Approval? approval,
  Telemetry? telemetry,
  required int maxDepth,
}) {
  late final WorkflowEngineImpl engine;
  engine = WorkflowEngineImpl(
    executor: buildNodeExecutor(
      engineOf: () => engine,
      team: team,
      tools: tools,
      maxDepth: maxDepth,
    ),
    store: store,
    hooks: WorkflowHooks(
      taskCenter: taskCenter,
      session: session,
      approval: approval,
      telemetry: telemetry,
      tools: tools,
      definitionOf: (String name) => engine.definition(name),
    ),
  );
  return engine;
}
