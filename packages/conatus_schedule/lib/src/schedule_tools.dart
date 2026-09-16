/// `schedule_list` 与 `schedule_delete`，以及三个工具的一次性注册。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'schedule.dart';
import 'schedule_create_tool.dart';
import 'schedule_errors.dart';
import 'schedule_tool_results.dart';
import 'schedule_types.dart';

/// 按创建顺序列出当前会话的活动提醒。
class ScheduleListTool extends Tool {
  /// 构造工具。
  const ScheduleListTool({required SessionSchedule schedule})
      : _schedule = schedule;

  final SessionSchedule _schedule;

  @override
  String get name => 'schedule_list';

  @override
  String get description =>
      'List every active reminder in the current session in creation order, '
      'including its exact id, UTC target, scheduled or overdue state, and '
      'session-local delivery mode.';

  @override
  String? get group => 'schedule';

  @override
  Future<ToolResult> call(ToolContext context) async {
    try {
      final List<ScheduleView> views = await _schedule.list();
      return scheduleSuccessResult(<Map<String, Object?>>[
        for (final ScheduleView view in views) view.toJson(),
      ]);
    } on SchedulePersistenceException catch (error) {
      return schedulePersistenceResult(error);
    } on ScheduleLogException {
      return scheduleCorruptResult();
    } on Object {
      return scheduleInternalResult();
    }
  }
}

/// 按标识删除一条活动提醒。
class ScheduleDeleteTool extends Tool {
  /// 构造工具。
  const ScheduleDeleteTool({required SessionSchedule schedule})
      : _schedule = schedule;

  final SessionSchedule _schedule;

  @override
  String get name => 'schedule_delete';

  @override
  String get description =>
      'Delete one active reminder in the current session by the exact id '
      'returned by schedule_create or schedule_list. Unknown or already-finished '
      'ids return deleted false.';

  @override
  ToolRisk get riskLevel => ToolRisk.medium;

  @override
  String? get group => 'schedule';

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('id',
            required: true, description: 'Exact session-local schedule id.'),
      ];

  @override
  Future<ToolResult> call(ToolContext context) async {
    final String? id = context.string('id');
    if (id == null || id.isEmpty || id.trim() != id) {
      return scheduleErrorResult(
        ScheduleErrorCode.invalidRule,
        'schedule_delete id must be non-empty without surrounding whitespace.',
      );
    }
    try {
      final ScheduleDeleteResult result = await _schedule.delete(id);
      return scheduleSuccessResult(result.toJson());
    } on SchedulePersistenceException catch (error) {
      return schedulePersistenceResult(error);
    } on ScheduleLogException {
      return scheduleCorruptResult();
    } on Object {
      return scheduleInternalResult();
    }
  }
}

/// 把三个提醒工具注册到 `ctx.tools`，返回已注册的工具。
///
/// [schedule] 缺省取上下文的 `'schedule'` 服务；[tools] 缺省取 `ctx.tools`。
List<Tool> provideScheduleTools(
  Context ctx, {
  SessionSchedule? schedule,
  ToolRegistry? tools,
}) {
  final SessionSchedule resolved = schedule ?? ctx.schedule;
  final ToolRegistry registry = tools ?? ctx.tools;
  final List<Tool> registered = <Tool>[
    ScheduleCreateTool(schedule: resolved),
    ScheduleListTool(schedule: resolved),
    ScheduleDeleteTool(schedule: resolved),
  ];
  for (final Tool tool in registered) {
    ctx.effect(() => registry.register(tool));
  }
  return registered;
}
