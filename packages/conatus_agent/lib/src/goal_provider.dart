/// goal 插件的装配。
///
/// [provideGoal] 提供 `'goal'` 服务，注册 `create_goal` / `edit_goal` /
/// `complete_goal` / `clear_goal` 四个工具，并经 `ctx.inject` 在
/// `agentLoop` 可用时创建 [GoalRoundDriver] 后置挂到 [AgentLoop.goalDriver]；
/// 依赖消失（或上下文释放）时自动摘除。`pause` / `resume` / `block` 不暴露
/// 给模型，由用户命令或续行驱动器调用。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'agent_loop.dart';
import 'approval.dart';
import 'goal_default.dart';
import 'goal_round_driver.dart';
import 'goal_service.dart';
import 'goal_tools.dart';
import 'telemetry.dart';

/// 提供 `'goal'` 服务并注册目标管理工具。
///
/// 依赖（全部可选，缺省时降级）：`session` 持久化 `goal/changed` 事件、
/// `systemPrompt` 注入 `goal` 段、`approval` clear / complete 确认（缺省
/// 自动批准）、`telemetry` 埋点；`tools` 必需，缺省取 `ctx.tools`。
GoalService provideGoal(
  Context ctx, {
  GoalService? goal,
  Session? session,
  SystemPrompt? prompt,
  ToolRegistry? tools,
  Approval? approval,
  Telemetry? telemetry,
  int defaultMaxRounds = 256,
}) {
  final GoalService resolved = goal ??
      DefaultGoalService(
        session: session,
        prompt: prompt,
        approval: approval,
        telemetry: telemetry,
        ctx: ctx,
        defaultMaxRounds: defaultMaxRounds,
      );
  final ToolRegistry registry = tools ?? ctx.tools;
  ctx.provide('goal', resolved);
  ctx.effect(() => registry.register(CreateGoalTool(goal: resolved)));
  ctx.effect(() => registry.register(EditGoalTool(goal: resolved)));
  ctx.effect(() => registry.register(CompleteGoalTool(goal: resolved)));
  ctx.effect(() => registry.register(ClearGoalTool(goal: resolved)));
  _attachDriver(ctx, resolved);
  ctx.onDispose(resolved.dispose);
  return resolved;
}

/// goal 与 agentLoop 齐备时创建 [GoalRoundDriver] 并挂到
/// [AgentLoop.goalDriver]。
void _attachDriver(Context ctx, GoalService goal) {
  ctx.inject(['agentLoop'], (child) {
    final AgentLoop agent = child.require<AgentLoop>('agentLoop');
    final GoalRoundDriver driver = GoalRoundDriver(goal: goal, agent: agent);
    agent.goalDriver = driver;
    child.provide('goalRoundDriver', driver);
    child.onDispose(() => agent.goalDriver = null);
  });
}
