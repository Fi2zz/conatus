/// cron 插件的封闭错误码与异常。
///
/// 错误码是稳定契约：工具结果里的 `code` 字段直接取这里的常量，模型据此区分
/// 输入错误、重复 id、目标不存在、配置任务保护与投递不可用。
library;

/// 封闭的 cron 错误码集合。
abstract final class CronErrorCode {
  /// 任务输入不合法（id、prompt、规则形状或规则取值）。
  static const String invalidTask = 'invalid-task';

  /// 任务 id 已存在。
  static const String duplicateId = 'duplicate-id';

  /// 目标任务不存在。
  static const String notFound = 'not-found';

  /// 目标任务是配置静态任务，运行时不可增删改。
  static const String configTask = 'config-task';

  /// 任务到期但投递端口不可用（宿主忙/无目标），下个 tick 重试。
  static const String deliveryUnavailable = 'delivery-unavailable';

  /// 不暴露内部细节的兜底失败。
  static const String internal = 'internal_error';
}

/// cron 服务抛出的稳定失败；[code] 取自 [CronErrorCode]。
class CronException implements Exception {
  /// 构造一个稳定的 cron 失败。
  const CronException(this.code, this.message);

  /// [CronErrorCode] 中的稳定错误码。
  final String code;

  /// 面向模型/宿主的可读诊断（与 dsh-cron 的消息保持一致）。
  final String message;

  @override
  String toString() => 'CronException($code): $message';
}
