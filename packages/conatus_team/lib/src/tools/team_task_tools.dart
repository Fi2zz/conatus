/// 面向模型的团队任务板工具：create / list / get / update。
///
/// 是 [AgentTeam] 任务板操作的薄封装；参数与 DSH 官方对齐。状态更新
/// 映射到 [AgentTeam.claimTask] / [completeTask] / [releaseTask]。
library;

import 'dart:async';

import 'package:conatus_foundation/conatus_foundation.dart';

import '../agent_team.dart';
import '../team_task.dart';

/// `team_task_create`：创建任务板任务。
class TeamTaskCreateTool extends Tool {
  TeamTaskCreateTool(this.team);
  final AgentTeam team;

  @override
  String get name => 'team_task_create';
  @override
  String get description => '在团队任务板上创建一个任务，可声明依赖与指派。';
  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('description', required: true),
        ParamSpec.array('depends_on', items: ParamSpec.string('item')),
        ParamSpec.string('assignee'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final TeamTask task = await team.createTask(
      description: ctx.str('description'),
      dependsOn: ctx.array('depends_on')?.map((Object? e) => '$e').toList() ??
          const <String>[],
      assigneeId: ctx.string('assignee'),
    );
    return ToolResult.success(task.id, value: task.toJson());
  }
}

/// `team_task_list`：列出任务，可按 status / assignee 过滤。
class TeamTaskListTool extends Tool {
  TeamTaskListTool(this.team);
  final AgentTeam team;

  @override
  String get name => 'team_task_list';
  @override
  String get description => '列出团队任务板上的任务，可按状态或指派者过滤。';
  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('status'),
        ParamSpec.string('assignee'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String? status = ctx.string('status');
    final String? assignee = ctx.string('assignee');
    final List<Map<String, Object?>> rows = team.tasks
        .where((TeamTask t) =>
            (status == null || t.status.name == status) &&
            (assignee == null || t.assigneeId == assignee))
        .map((TeamTask t) => t.toJson())
        .toList(growable: false);
    return ToolResult.success('${rows.length} 个任务', value: rows);
  }
}

/// `team_task_get`：查询单个任务。
class TeamTaskGetTool extends Tool {
  TeamTaskGetTool(this.team);
  final AgentTeam team;

  @override
  String get name => 'team_task_get';
  @override
  String get description => '按 id 查询团队任务板上的单个任务。';
  @override
  List<ParamSpec> get params =>
      <ParamSpec>[ParamSpec.string('task_id', required: true)];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final TeamTask? task = team.task(ctx.str('task_id'));
    if (task == null) {
      return ToolResult.failure('任务不存在',
          error: const ToolError('not-found', '任务不存在'));
    }
    return ToolResult.success(task.description, value: task.toJson());
  }
}

/// `team_task_update`：更新任务状态（claimed / done / released）。
class TeamTaskUpdateTool extends Tool {
  TeamTaskUpdateTool(this.team);
  final AgentTeam team;

  @override
  String get name => 'team_task_update';
  @override
  String get description => '更新任务状态：claimed（领取）/ done（完成）/ released（释放）。';
  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('task_id', required: true),
        ParamSpec.string('teammate_id', required: true),
        ParamSpec.string('status', required: true),
        ParamSpec.string('result'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String taskId = ctx.str('task_id');
    final String teammateId = ctx.str('teammate_id');
    final String status = ctx.str('status');
    final TeamTask task;
    switch (status) {
      case 'claimed':
        task = await team.claimTask(taskId, teammateId);
        break;
      case 'done':
        task = await team.completeTask(taskId, teammateId,
            result: ctx.string('result'));
        break;
      case 'released':
        task = await team.releaseTask(taskId, teammateId);
        break;
      default:
        return ToolResult.failure('不支持的状态：$status',
            error: ToolError('bad-status', '不支持的状态：$status'));
    }
    return ToolResult.success(task.id, value: task.toJson());
  }
}
