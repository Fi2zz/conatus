/// Workflow 的错误类型。
library;

/// Workflow 相关错误。
class WorkflowException implements Exception {
  const WorkflowException(this.code, this.message);

  /// 稳定的机器可读错误码（如 `missing-field` / `bad-type` /
  /// `unknown-node-type`）。
  final String code;

  /// 面向用户/模型的可读消息。
  final String message;

  @override
  String toString() => 'WorkflowException($code): $message';
}
