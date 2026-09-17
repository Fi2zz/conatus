/// 团队工具装配：把 10 个团队工具注册到 [ToolRegistry]。
///
/// 调用 [provideTeamTools] 一次性注册全部工具；工具随 [ctx] 释放自动
/// 撤销注册。`spawn_teammate` 与 `interrupt_agent` 是 medium 风险，
/// [AgentTeam.spawn] / [interrupt] 内部已挂 [TeamHooks] 的 approval
/// seam，无需工具层再拦一次。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import '../agent_team.dart';
import '../team_impl.dart' show TeamContext;
import 'team_member_tools.dart';
import 'team_task_tools.dart';

/// 把 10 个团队工具注册到 [ctx] 的 `tools` 服务。
///
/// - [team]：缺省取 `ctx.team`（需先 [provideAgentTeam]）。
/// - [tools]：缺省取 `ctx.tools`。
void provideTeamTools(
  Context ctx, {
  AgentTeam? team,
  ToolRegistry? tools,
}) {
  final AgentTeam resolved = team ?? ctx.team;
  final ToolRegistry registry = tools ?? ctx.tools;
  for (final Tool tool in <Tool>[
    SpawnTeammateTool(resolved),
    SendMessageTool(resolved),
    FollowupTaskTool(resolved),
    ListAgentsTool(resolved),
    WaitAgentTool(resolved),
    InterruptAgentTool(resolved),
    TeamTaskCreateTool(resolved),
    TeamTaskListTool(resolved),
    TeamTaskGetTool(resolved),
    TeamTaskUpdateTool(resolved),
  ]) {
    ctx.effect(() => registry.register(tool));
  }
}
