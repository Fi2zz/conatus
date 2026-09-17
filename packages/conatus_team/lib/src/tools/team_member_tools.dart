/// 面向模型的团队成员工具：spawn / send / followup / list / wait / interrupt。
///
/// 是 [AgentTeam] 成员操作的薄封装。[SpawnTeammateTool] 与
/// [InterruptAgentTool] 为 medium 风险，运行时由 [TeamHooks] 的
/// approval seam 拦截（[AgentTeam.spawn] / [interrupt] 内部已挂审批）。
library;

import 'dart:async';

import 'package:conatus_foundation/conatus_foundation.dart';

import '../agent_team.dart';
import '../teammate.dart';

/// `spawn_teammate`：创建团队成员（medium 风险，走审批）。
class SpawnTeammateTool extends Tool {
  SpawnTeammateTool(this.team);
  final AgentTeam team;

  @override
  String get name => 'spawn_teammate';
  @override
  String get description => '创建一个团队成员，可指定工具白名单与角色提示。';
  @override
  ToolRisk get riskLevel => ToolRisk.medium;
  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('name', required: true),
        ParamSpec.array('tools', items: ParamSpec.string('item')),
        ParamSpec.string('system_prompt'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final Teammate m = await team.spawn(
      name: ctx.str('name'),
      tools: ctx.array('tools')?.map((Object? e) => '$e').toList(),
      systemPrompt: ctx.string('system_prompt'),
    );
    return ToolResult.success('已创建成员 ${m.name}', value: m.toJson());
  }
}

/// `send_message`：给指定成员发一条消息。
class SendMessageTool extends Tool {
  SendMessageTool(this.team);
  final AgentTeam team;

  @override
  String get name => 'send_message';
  @override
  String get description => '向指定团队成员发送一条消息，成员下一轮读到。';
  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('teammate_id', required: true),
        ParamSpec.string('message', required: true),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    await team.send(ctx.str('teammate_id'), ctx.str('message'));
    return ToolResult.success('已发送');
  }
}

/// `followup_task`：给成员追加一个任务（等价 send 任务消息）。
class FollowupTaskTool extends Tool {
  FollowupTaskTool(this.team);
  final AgentTeam team;

  @override
  String get name => 'followup_task';
  @override
  String get description => '向指定成员追加一个任务，成员处理完后回报。';
  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('teammate_id', required: true),
        ParamSpec.string('task', required: true),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    await team.send(ctx.str('teammate_id'), ctx.str('task'));
    return ToolResult.success('已追加任务');
  }
}

/// `list_agents`：列出当前所有成员。
class ListAgentsTool extends Tool {
  ListAgentsTool(this.team);
  final AgentTeam team;

  @override
  String get name => 'list_agents';
  @override
  String get description => '列出当前团队的所有成员及其状态。';
  @override
  List<ParamSpec> get params => const <ParamSpec>[];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final List<Map<String, Object?>> rows =
        team.members.map((Teammate m) => m.toJson()).toList(growable: false);
    return ToolResult.success('${rows.length} 个成员', value: rows);
  }
}

/// `wait_agent`：等指定成员完成当前工作。
class WaitAgentTool extends Tool {
  WaitAgentTool(this.team);
  final AgentTeam team;

  @override
  String get name => 'wait_agent';
  @override
  String get description => '等待指定成员完成当前工作，返回其最新状态。';
  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('teammate_id', required: true),
        ParamSpec.integer('timeout_ms'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final int? ms = ctx.integer('timeout_ms');
    final Teammate m = await team.wait(ctx.str('teammate_id'),
        timeout: ms == null ? null : Duration(milliseconds: ms));
    return ToolResult.success(m.name, value: m.toJson());
  }
}

/// `interrupt_agent`：中断指定成员（medium 风险，走审批）。
class InterruptAgentTool extends Tool {
  InterruptAgentTool(this.team);
  final AgentTeam team;

  @override
  String get name => 'interrupt_agent';
  @override
  String get description => '中断指定成员的当前工作。';
  @override
  ToolRisk get riskLevel => ToolRisk.medium;
  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('teammate_id', required: true),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    await team.interrupt(ctx.str('teammate_id'));
    return ToolResult.success('已中断');
  }
}
