/// 代码执行结果。失败是结果字段，不是异常。
library;

/// 一次代码执行的结果。
class CodeRunResult {
  const CodeRunResult({
    this.value,
    this.logs = const <String>[],
    this.error,
  });

  /// 执行返回值（子进程后端为 stdout 文本）。
  final Object? value;

  /// 执行日志（子进程后端为 stderr 按行拆分）。
  final List<String> logs;

  /// 失败详情；成功时为 null。
  final CodeRunFailure? error;

  /// 是否成功。
  bool get isSuccess => error == null;

  /// 成功结果。
  factory CodeRunResult.success(Object? value,
          {List<String> logs = const []}) =>
      CodeRunResult(value: value, logs: logs);

  /// 失败结果。
  factory CodeRunResult.failure(CodeRunFailureKind kind, String message) =>
      CodeRunResult(error: CodeRunFailure(kind, message));
}

/// 失败类型。
enum CodeRunFailureKind {
  /// 程序抛异常或非零退出。
  exception,

  /// 超出 [CodeRunLimits.maxDuration]。
  timeout,

  /// 执行被外部中止。
  abort,

  /// 工作进程退出（供支持工作进程的后端使用）。
  workerExit,

  /// 返回值无法序列化（供支持返回值求值的后端使用）。
  invalidOutput,

  /// 输出超出 [CodeRunLimits.maxOutputBytes]。
  outputLimit,
}

/// 失败详情。
class CodeRunFailure {
  const CodeRunFailure(this.kind, this.message);

  /// 失败类型。
  final CodeRunFailureKind kind;

  /// 面向人的说明。
  final String message;
}
