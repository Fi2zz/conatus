/// cron 工具的统一结果形状。
///
/// 工具结果对模型是规范 JSON 文本：成功时是视图或记录数组，失败时是
/// `{code, message}`。错误码取自封闭集合 [CronErrorCode]。
library;

import 'dart:convert';

import 'package:conatus_foundation/conatus_foundation.dart';

import 'cron_errors.dart';

/// 成功结果：规范值同时作为文本与结构化值返回。
ToolResult cronSuccessResult(Object? value) =>
    ToolResult.success(jsonEncode(value), value: value);

/// 失败结果：文本是 `{code, message}` 的 JSON，错误码透传给宿主。
ToolResult cronErrorResult(String code, String message) => ToolResult.failure(
      jsonEncode(<String, Object?>{'code': code, 'message': message}),
      error: ToolError(code, message),
    );

/// 不暴露内部细节的兜底失败结果。
ToolResult cronInternalResult() =>
    cronErrorResult(CronErrorCode.internal, 'The cron operation failed.');
