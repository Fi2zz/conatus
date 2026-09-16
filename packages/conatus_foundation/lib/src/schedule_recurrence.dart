/// 固定间隔提醒的发生时点算术。
///
/// 决策只取「最新一个已到期且与创建锚点对齐」的发生时点，并用整数运算直接推进到
/// 第一个未来目标：错过的间隔**永远不会**被逐条枚举，因此不会回放积压。
library;

import 'schedule_errors.dart';
import 'schedule_time.dart';
import 'schedule_types.dart';

/// 一次固定间隔决策的产生结果。
class EveryOccurrence {
  /// 构造一次决策结果。
  const EveryOccurrence({required this.occurrenceAt, this.nextScheduledAt});

  /// 最新一个已到期的锚点对齐发生时点。
  final DateTime occurrenceAt;

  /// 第一个严格未来的锚点对齐目标；已经耗尽（超范围）时为 `null`。
  final DateTime? nextScheduledAt;
}

/// 计算 [record] 在 [acceptedAt] 时点最新一个到期时点及下一个目标。
EveryOccurrence resolveEveryOccurrence(
  ScheduleRecord record,
  DateTime acceptedAt,
) {
  final int? everySeconds = record.everySeconds;
  if (record.kind != ScheduleKind.every || everySeconds == null) {
    throw const ScheduleLogException(
        'every occurrence requires a fixed-rate record');
  }
  if (acceptedAt.isBefore(minFourDigitYearInstant) ||
      acceptedAt.isAfter(maxFourDigitYearInstant)) {
    throw const ScheduleLogException(
        'every acceptedAt must be a representable four-digit-year instant');
  }
  if (everySeconds <= 0 || everySeconds > kMaxSafeInteger ~/ 1000) {
    throw const ScheduleLogException(
        'every interval milliseconds must be a positive safe integer');
  }
  final int interval = everySeconds * 1000;
  final int target = record.scheduledAt.millisecondsSinceEpoch;
  final int accepted = acceptedAt.millisecondsSinceEpoch;
  if (accepted < target) {
    throw const ScheduleLogException(
        'every dispatch cannot precede the active scheduledAt');
  }
  final int occurrence = target + (accepted - target) ~/ interval * interval;
  final int next = occurrence + interval;
  return EveryOccurrence(
    occurrenceAt: DateTime.fromMillisecondsSinceEpoch(occurrence, isUtc: true),
    nextScheduledAt: next > maxFourDigitYearInstant.millisecondsSinceEpoch
        ? null
        : DateTime.fromMillisecondsSinceEpoch(next, isUtc: true),
  );
}
