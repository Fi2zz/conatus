/// tools 插件的调用词汇：请求、结局、风险等级与管线签名。
library;

/// 一次工具调用的请求。
///
/// [arguments] 是解析后的参数对象；[callId] 由调用方提供，用于回喂与关联。
class ToolCall {
  const ToolCall({
    required this.name,
    this.callId = '',
    this.arguments = const <String, Object?>{},
  });

  /// 调用标识；缺省为空。
  final String callId;

  /// 工具名（注册表键）。
  final String name;

  /// 解析后的参数对象。
  final Map<String, Object?> arguments;

  @override
  String toString() => 'ToolCall($name)';
}

/// 工具失败的结构化信息。
class ToolError {
  const ToolError(this.code, this.message);

  /// 稳定的机器可读错误码。
  final String code;

  /// 面向模型/用户的可读消息。
  final String message;

  @override
  String toString() => '$code: $message';
}

/// 一次工具调用的结局：成功携带规范值 [value]，失败携带 [error]。
class ToolResult {
  ToolResult.success(this.content, {this.value})
      : isError = false,
        error = null;

  ToolResult.failure(this.content, {this.error})
      : isError = true,
        value = null;

  /// 是否失败。
  final bool isError;

  /// 模型可见的文本内容。
  final String content;

  /// 执行体返回的规范值；失败时为 null。
  final Object? value;

  /// 失败详情；成功时为 null。
  final ToolError? error;

  @override
  String toString() =>
      isError ? 'ToolResult.failure(${error?.code})' : 'ToolResult.success';
}

/// 工具风险等级。
///
/// [low] 只读、[medium] 有副作用但可回退、[high] 破坏性或需确认；能力分级与
/// 确认门控在更大规模时读取该字段。
enum ToolRisk { low, medium, high }

/// 单调守卫：返回非空理由即拒绝该次调用，返回 `null` 放行。
typedef ToolGuard = String? Function(ToolCall call);

/// 环绕执行的中间件：`next()` 交给后续管线（含工具执行体）。
typedef ToolMiddleware = Future<ToolResult> Function(
  ToolCall call,
  Future<ToolResult> Function() next,
);

/// 结果观察者。
typedef ToolResultListener = void Function(ToolCall call, ToolResult result);
