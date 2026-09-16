/// schedule 插件的封闭错误码与两类异常。
///
/// 错误码是稳定契约：工具结果里的 `code` 字段直接取这里的常量，模型据此区分输入
/// 错误、规则错误、时间错误与持久日志损坏；新增错误码属于协议变更。
library;

/// 封闭的 schedule 错误码集合。
abstract final class ScheduleErrorCode {
  /// 提醒内容去空白后为空。
  static const String invalidPrompt = 'invalid_prompt';

  /// 选择器缺失、冲突，或出现未知的创建参数。
  static const String invalidSelector = 'invalid_selector';

  /// 规则本身非法（选择器取值、`at` 形状、删除参数格式）。
  static const String invalidRule = 'invalid_rule';

  /// `time_zone` 不是 `UTC` 或合法的 IANA `Area/Location` 名。
  static const String invalidTimeZone = 'invalid_time_zone';

  /// 计算出的时刻不严格晚于创建时刻。
  static const String notFuture = 'not_future';

  /// 时刻无法用四位年份的 RFC 3339 UTC 形式表示。
  static const String timeOutOfRange = 'time_out_of_range';

  /// 固定间隔低于 300 秒。
  static const String frequencyTooHigh = 'frequency_too_high';

  /// 会话里的 schedule 变更流已损坏。
  static const String corruptLog = 'corrupt_schedule_log';

  /// 无法确认持久化是否落定。
  static const String persistenceUncertain = 'persistence_uncertain';

  /// 不暴露内部细节的兜底失败。
  static const String internal = 'internal_error';

  /// 删除目标不存在或已经结束。
  static const String notFound = 'schedule_not_found';
}

/// 模型给出的规则无法成为一条持久记录。
class ScheduleInputException implements Exception {
  /// 构造一个稳定的输入失败。
  const ScheduleInputException(this.code, this.message);

  /// [ScheduleErrorCode] 中的稳定错误码。
  final String code;

  /// 面向模型的稳定诊断。
  final String message;

  @override
  String toString() => 'ScheduleInputException($code): $message';
}

/// 会话里的持久 schedule 流损坏，或出现了非法转换。
class ScheduleLogException implements Exception {
  /// 构造一个持久日志失败。
  const ScheduleLogException(this.message);

  /// 固定为 `corrupt_schedule_log`。
  String get code => ScheduleErrorCode.corruptLog;

  /// 被违反的具体不变式。
  final String message;

  @override
  String toString() => 'ScheduleLogException: $message';
}

/// 可能无法确认落定的管理操作名。
abstract final class ScheduleOperation {
  /// 创建一条提醒。
  static const String create = 'create';

  /// 列出活动提醒。
  static const String list = 'list';

  /// 删除一条提醒。
  static const String delete = 'delete';
}

/// 无法确认持久化是否落定。
///
/// 这不是「失败」：变更可能已经写进会话，也可能没有。调用方应当先用
/// `schedule_list` 澄清，而不是重试或声称成功。
class SchedulePersistenceException implements Exception {
  /// 构造一个持久化不确定的失败。
  const SchedulePersistenceException(this.operation, [this.id]);

  /// [ScheduleOperation] 中的操作名。
  final String operation;

  /// 已知的目标标识（创建与删除才有）。
  final String? id;

  /// 固定为 `persistence_uncertain`。
  String get code => ScheduleErrorCode.persistenceUncertain;

  @override
  String toString() => 'SchedulePersistenceException($operation)';
}
