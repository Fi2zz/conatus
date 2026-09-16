/// `cron_list` / `cron_history` 两个只读工具，以及五个 cron 工具的一次性注册。
///
/// 工具结果对模型是规范 JSON 文本：成功时是视图或记录数组，失败时是
/// `{code, message}`。错误码取自封闭集合 [CronErrorCode]。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'cron.dart';
import 'cron_edit_tools.dart';
import 'cron_errors.dart';
import 'cron_history.dart';
import 'cron_runtime.dart';
import 'cron_tool_results.dart';
import 'cron_types.dart';

/// 列出全部定时任务（配置 + 动态）及其状态与下次触发时刻。
class CronListTool extends Tool {
  /// 构造工具。
  const CronListTool({required CronService service}) : _service = service;

  final CronService _service;

  @override
  String get name => 'cron_list';

  @override
  String get description =>
      'List all scheduled tasks (from config and added at runtime) with '
      'their state and next run time.';

  @override
  Future<ToolResult> call(ToolContext context) async {
    try {
      return cronSuccessResult(<Map<String, Object?>>[
        for (final CronTaskView view in _service.listTasks()) view.toJson(),
      ]);
    } on CronException catch (error) {
      return cronErrorResult(error.code, error.message);
    } on Object {
      return cronInternalResult();
    }
  }
}

/// 查看最近的任务执行记录（最新在前）。
class CronHistoryTool extends Tool {
  /// 构造工具。
  const CronHistoryTool({required CronService service}) : _service = service;

  final CronService _service;

  @override
  String get name => 'cron_history';

  @override
  String get description =>
      'Show recent scheduled-task execution records: when each task fired, '
      'whether it completed, and a short result excerpt.';

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.integer('limit',
            description: 'Max records to return (default 20, newest first).'),
      ];

  @override
  Future<ToolResult> call(ToolContext context) async {
    try {
      final List<CronRunRecord> records =
          _service.listHistory(limit: context.integer('limit') ?? 20);
      return cronSuccessResult(<Map<String, Object?>>[
        for (final CronRunRecord record in records) record.toJson(),
      ]);
    } on CronException catch (error) {
      return cronErrorResult(error.code, error.message);
    } on Object {
      return cronInternalResult();
    }
  }
}

/// 把五个 cron 工具注册到 `ctx.tools`，返回已注册的工具。
///
/// [service] 缺省取上下文的 `'cron'` 服务；[runtime] 为预留参数（后续
/// `cron_run` 立即执行工具需要运行时投递端口）。
List<Tool> provideCronTools(
  Context ctx, {
  CronService? service,
  CronRuntime? runtime,
}) {
  final CronService resolved = service ?? ctx.cron;
  final List<Tool> registered = <Tool>[
    CronListTool(service: resolved),
    CronHistoryTool(service: resolved),
    CronAddTool(service: resolved),
    CronUpdateTool(service: resolved),
    CronRemoveTool(service: resolved),
  ];
  for (final Tool tool in registered) {
    ctx.effect(() => ctx.tools.register(tool));
  }
  return registered;
}
