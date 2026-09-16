/// 提醒工具的统一结果形状。
///
/// 工具结果对模型是规范 JSON 文本：成功时是记录视图或视图数组，失败时是
/// `{code, message}`。错误码取自封闭集合 [ScheduleErrorCode]。
library;

import 'dart:convert';

import 'schedule_errors.dart';
import 'tool_types.dart';

/// 成功结果：规范值同时作为文本与结构化值返回。
ToolResult scheduleSuccessResult(Object? value) =>
    ToolResult.success(jsonEncode(value), value: value);

/// 失败结果：文本是 `{code, message}` 的 JSON，错误码透传给宿主。
ToolResult scheduleErrorResult(String code, String message) =>
    ToolResult.failure(
      jsonEncode(<String, Object?>{'code': code, 'message': message}),
      error: ToolError(code, message),
    );

/// 持久化不确定的失败结果；调用方应先用 `schedule_list` 澄清。
ToolResult schedulePersistenceResult(SchedulePersistenceException error) =>
    scheduleErrorResult(
      ScheduleErrorCode.persistenceUncertain,
      'Schedule persistence is uncertain; retry with schedule_list before '
      'relying on this result.',
    );

/// 持久日志损坏的失败结果；具体不变式只用于日志，不暴露给模型。
ToolResult scheduleCorruptResult() => scheduleErrorResult(
    ScheduleErrorCode.corruptLog, 'The session schedule log is corrupt.');

/// 不暴露内部细节的兜底失败结果。
ToolResult scheduleInternalResult() => scheduleErrorResult(
    ScheduleErrorCode.internal, 'The schedule operation failed.');
