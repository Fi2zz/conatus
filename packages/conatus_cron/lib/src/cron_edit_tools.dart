/// `cron_add` / `cron_update` / `cron_remove` 三个管理工具。
///
/// 工具层只做参数读取与 CronException 到 ToolResult 的转换，语义全在服务。
/// 会话绑定：显式 `session_id` 参数优先，否则用工具构造时传入的调用方会话
/// id（宿主按会话装配工具实例时），再否则读宿主注入的 `_session_id` 参数。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import 'cron.dart';
import 'cron_errors.dart';
import 'cron_tool_results.dart';
import 'cron_types.dart';

/// 添加一个定时任务；四选一规则，id 缺省自动生成。
class CronAddTool extends Tool {
  /// 构造工具；[callerSessionId] 绑定调用方会话（任务触发时回到该会话）。
  const CronAddTool({required CronService service, String? callerSessionId})
      : _service = service,
        _callerSessionId = callerSessionId;

  final CronService _service;
  final String? _callerSessionId;

  @override
  String get name => 'cron_add';

  @override
  String get description =>
      'Add a scheduled task. Set exactly one rule: at (ISO instant, one-shot), '
      'every (interval seconds, min 10), daily ("HH:MM" local time), or cron '
      '(standard 5-field expression "minute hour day month weekday", local time '
      '— e.g. "0 9 * * *" = daily 09:00, "*/30 * * * *" = every 30 min, '
      '"0 9 * * 1" = Mondays 09:00). Convert the user\'s natural-language schedule '
      'into one of these rules. The task prompt is delivered to the agent '
      'automatically when due and the result is replied in the conversation. '
      'Dynamic tasks persist across restarts.';

  @override
  ToolRisk get riskLevel => ToolRisk.medium;

  @override
  String? get group => 'cron';

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('id',
            description:
                'Optional unique task id (letters, digits, -, _). One is generated when omitted.'),
        ParamSpec.string('prompt',
            required: true,
            description: 'What the agent should do when the task fires.'),
        ParamSpec.string('at',
            description: 'ISO 8601 instant for a one-shot task.'),
        ParamSpec.number('every',
            description:
                'Fixed interval in seconds (min $kCronMinEverySeconds).'),
        ParamSpec.string('daily',
            description: 'Local wall-clock "HH:MM" for a daily task.'),
        ParamSpec.string('cron',
            description:
                'Standard 5-field cron expression (minute hour day month weekday), local time.'),
        ParamSpec.string('session_id',
            description:
                'Bind the task to one session id: runs are delivered there.'),
      ];

  @override
  Future<ToolResult> call(ToolContext context) async {
    try {
      final CronTaskView view = _service.addDynamicTask(
        _taskInput(context),
        callerSessionId: _resolveCallerSession(context),
      );
      return cronSuccessResult(view.toJson());
    } on CronException catch (error) {
      return cronErrorResult(error.code, error.message);
    } on Object {
      return cronInternalResult();
    }
  }

  /// 模型侧的 `session_id` 参数映射为服务输入的 `sessionId`（显式值优先）。
  Map<String, Object?> _taskInput(ToolContext context) {
    final Map<String, Object?> input =
        Map<String, Object?>.of(context.arguments);
    final String? sessionId = context.string('session_id');
    input.remove('session_id');
    if (sessionId != null) input['sessionId'] = sessionId;
    return input;
  }

  String? _resolveCallerSession(ToolContext context) =>
      context.optional<String>('_session_id') ?? _callerSessionId;
}

/// 编辑动态任务的 prompt 或整组替换排期规则。
class CronUpdateTool extends Tool {
  /// 构造工具。
  const CronUpdateTool({required CronService service}) : _service = service;

  final CronService _service;

  @override
  String get name => 'cron_update';

  @override
  String get description =>
      'Edit a dynamically added scheduled task: change its prompt and/or '
      'replace its schedule rule. Pass exactly one rule (at / every / daily / '
      'cron) to change the schedule; omitted fields stay unchanged. Tasks '
      'declared in host config cannot be edited at runtime.';

  @override
  ToolRisk get riskLevel => ToolRisk.medium;

  @override
  String? get group => 'cron';

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('id', required: true, description: 'Id of the task to edit.'),
        ParamSpec.string('prompt', description: 'New task prompt.'),
        ParamSpec.string('at',
            description: 'Replace the schedule with a one-shot ISO 8601 instant.'),
        ParamSpec.number('every',
            description:
                'Replace the schedule with a fixed interval in seconds (min $kCronMinEverySeconds).'),
        ParamSpec.string('daily',
            description: 'Replace the schedule with a daily local "HH:MM".'),
        ParamSpec.string('cron',
            description:
                'Replace the schedule with a standard 5-field cron expression.'),
      ];

  @override
  Future<ToolResult> call(ToolContext context) async {
    final String? id = context.string('id');
    if (id == null || id.isEmpty) {
      return cronErrorResult(
          CronErrorCode.invalidTask, 'cron_update id must be non-empty.');
    }
    try {
      final CronTaskView view =
          _service.updateDynamicTask(id, context.arguments);
      return cronSuccessResult(view.toJson());
    } on CronException catch (error) {
      return cronErrorResult(error.code, error.message);
    } on Object {
      return cronInternalResult();
    }
  }
}

/// 按 id 删除动态任务；配置任务拒绝删除。
class CronRemoveTool extends Tool {
  /// 构造工具。
  const CronRemoveTool({required CronService service}) : _service = service;

  final CronService _service;

  @override
  String get name => 'cron_remove';

  @override
  String get description =>
      'Remove a dynamically added scheduled task by id. Tasks declared in host '
      'config cannot be removed at runtime.';

  @override
  ToolRisk get riskLevel => ToolRisk.medium;

  @override
  String? get group => 'cron';

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('id',
            required: true, description: 'Id of the task to remove.'),
      ];

  @override
  Future<ToolResult> call(ToolContext context) async {
    final String? id = context.string('id');
    if (id == null || id.isEmpty) {
      return cronErrorResult(
          CronErrorCode.invalidTask, 'cron_remove id must be non-empty.');
    }
    try {
      _service.removeDynamicTask(id);
      return cronSuccessResult(<String, Object?>{'removed': id});
    } on CronException catch (error) {
      return cronErrorResult(error.code, error.message);
    } on Object {
      return cronInternalResult();
    }
  }
}
