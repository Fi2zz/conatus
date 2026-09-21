/// 代码执行请求与资源限制。
library;

/// 一次代码执行请求。
class CodeRunRequest {
  const CodeRunRequest({
    required this.program,
    this.bindings = const <CodeBindingNamespace>[],
    this.timeout,
    this.limits,
  });

  /// 待执行的源代码。
  final String program;

  /// 注入执行环境的绑定命名空间；子进程后端忽略，供支持绑定的后端使用。
  final List<CodeBindingNamespace> bindings;

  /// 单次执行超时；缺省用 [CodeRunLimits.maxDuration]。
  final Duration? timeout;

  /// 资源限制；缺省用 [CodeRunLimits] 默认值。
  final CodeRunLimits? limits;
}

/// 资源限制。
class CodeRunLimits {
  const CodeRunLimits({
    this.maxMemoryMb,
    this.maxOutputBytes = 1024 * 1024,
    this.maxDuration = const Duration(seconds: 30),
  });

  /// 内存上限（MB）；null 表示不限制。
  final int? maxMemoryMb;

  /// stdout 采集上限（字节）。
  final int maxOutputBytes;

  /// 最长执行时长。
  final Duration maxDuration;
}

/// 绑定函数：接收参数映射，返回异步结果。
typedef CodeBindingFn = Future<Object?> Function(Map<String, Object?>);

/// 绑定命名空间：把一个全局名映射到一组可调用函数。
class CodeBindingNamespace {
  const CodeBindingNamespace({
    required this.global,
    required this.functions,
  });

  /// 注入执行环境的全局名，如 'tools'。
  final String global;

  /// 函数名 → 调用入口。
  final Map<String, CodeBindingFn> functions;
}
