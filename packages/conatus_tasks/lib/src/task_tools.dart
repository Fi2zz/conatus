/// task 插件的模型侧工具。
///
/// 两个工具注册到 `ToolRegistry`：`list_tasks`（low，只读）与
/// `cancel_task`（medium，走 approval 确认）。返回文本面向语音场景口语化。
/// `create` 不暴露给模型——任务由运行时组件（Agent Loop / sub-agent /
/// shell / schedule）自动创建。
library;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'task.dart';
import 'task_center.dart';

/// `list_tasks` 工具名。
const String kListTasksToolName = 'list_tasks';

/// `cancel_task` 工具名。
const String kCancelTasksToolName = 'cancel_task';

/// 把任务列表格式化为口语化播报文本（语音场景）。
String describeTasks(List<Task> tasks) {
  if (tasks.isEmpty) return '现在没有任务。';
  final StringBuffer buffer = StringBuffer('现在共 ${tasks.length} 个任务：');
  for (int i = 0; i < tasks.length; i++) {
    final Task task = tasks[i];
    buffer.write('\n${i + 1}. ${task.description}（${_statusText(task.status)}');
    final Duration? duration = task.duration;
    if (duration != null) buffer.write('，已运行 ${_durationText(duration)}');
    buffer.write('）');
  }
  return buffer.toString();
}

/// 列出当前任务。可按状态、类型、父任务过滤。
class ListTasksTool extends Tool {
  /// 提交任务 [TaskCenter]。
  const ListTasksTool({required this.taskCenter});

  /// 任务中心。
  final TaskCenter taskCenter;

  @override
  String get name => kListTasksToolName;

  @override
  String get description => '列出当前任务。可按状态、类型、父任务过滤。';

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.enumeration(
          'status',
          <String>[
            'pending',
            'running',
            'paused',
            'completed',
            'failed',
            'cancelled',
          ],
          description: '按状态过滤',
        ),
        ParamSpec.enumeration(
          'kind',
          <String>['agentTurn', 'subAgent', 'shell', 'schedule', 'custom'],
          description: '按类型过滤',
        ),
        ParamSpec.string('parent_id', description: '按父任务过滤'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    List<Task> tasks = taskCenter.all;
    final String? status = ctx.string('status');
    if (status != null) {
      tasks = tasks.where((Task t) => t.status.name == status).toList();
    }
    final String? kind = ctx.string('kind');
    if (kind != null) {
      tasks = tasks.where((Task t) => t.kind.name == kind).toList();
    }
    final String? parentId = ctx.string('parent_id');
    if (parentId != null) {
      tasks = tasks.where((Task t) => t.parentTaskId == parentId).toList();
    }
    return ToolResult.success(describeTasks(tasks));
  }
}

/// 取消任务（shell 类任务走 approval 确认）。
class CancelTaskTool extends Tool {
  /// 提交任务 [TaskCenter]。
  const CancelTaskTool({required this.taskCenter});

  /// 任务中心。
  final TaskCenter taskCenter;

  @override
  String get name => kCancelTasksToolName;

  @override
  String get description => '取消一个任务，会同时取消其所有子任务。';

  @override
  ToolRisk get riskLevel => ToolRisk.medium;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('id', required: true, description: '任务 ID'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    try {
      final String id = ctx.str('id');
      await taskCenter.cancel(id);
      final Task? task = taskCenter.get(id);
      return ToolResult.success('好的，已取消任务「${task?.description ?? id}」。');
    } on TaskException catch (e) {
      return ToolResult.failure(e.message, error: ToolError(e.code, e.message));
    }
  }
}

String _statusText(TaskStatus status) => switch (status) {
      TaskStatus.pending => '等待中',
      TaskStatus.running => '进行中',
      TaskStatus.paused => '已暂停',
      TaskStatus.completed => '已完成',
      TaskStatus.failed => '已失败',
      TaskStatus.cancelled => '已取消',
    };

String _durationText(Duration duration) {
  final int minutes = duration.inMinutes;
  if (minutes >= 1) return '$minutes 分钟';
  final int seconds = duration.inSeconds;
  return '$seconds 秒';
}
