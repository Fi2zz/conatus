/// 创建规则：把模型给出的选择器校验成一条持久记录，并派生模型可见视图。
///
/// 三个创建函数的错误码与顺序属于协议：先校验提醒内容，再校验选择器本身，
/// 最后校验目标时刻是否严格位于未来且在可表示范围内。
library;

import 'schedule_errors.dart';
import 'schedule_time.dart';
import 'schedule_time_zone.dart';
import 'schedule_types.dart';

/// 规范提醒内容：去首尾空白，并拒绝空内容。
String normalizePrompt(String prompt) {
  final String normalized = prompt.trim();
  if (normalized.isEmpty) {
    throw const ScheduleInputException(ScheduleErrorCode.invalidPrompt,
        'prompt must be non-empty after trimming.');
  }
  return normalized;
}

/// 校验延迟规则并构造一条 `after` 记录。
ScheduleRecord createAfterRecord({
  required String id,
  required String prompt,
  required Object? afterSeconds,
  required DateTime now,
}) {
  final String normalized = normalizePrompt(prompt);
  if (afterSeconds is! int || !safePositiveSeconds(afterSeconds)) {
    throw const ScheduleInputException(ScheduleErrorCode.invalidRule,
        'after_seconds must be a positive safe integer.');
  }
  return ScheduleRecord(
    id: id,
    kind: ScheduleKind.after,
    prompt: normalized,
    afterSeconds: afterSeconds,
    scheduledAt: futureInstant(now.add(Duration(seconds: afterSeconds)), now),
  );
}

/// 校验绝对时刻选择器并构造一条 `at` 记录。
ScheduleRecord createAtRecord({
  required String id,
  required String prompt,
  required Object? at,
  required DateTime now,
}) {
  final String normalized = normalizePrompt(prompt);
  final DateTime target = resolveAtTarget(at);
  return ScheduleRecord(
    id: id,
    kind: ScheduleKind.at,
    prompt: normalized,
    scheduledAt: futureInstant(target, now),
  );
}

/// 校验固定间隔规则并构造一条 `every` 记录。
ScheduleRecord createEveryRecord({
  required String id,
  required String prompt,
  required Object? everySeconds,
  required DateTime now,
}) {
  final String normalized = normalizePrompt(prompt);
  if (everySeconds is! int || everySeconds > kMaxSafeInteger) {
    throw const ScheduleInputException(
        ScheduleErrorCode.invalidRule, 'every_seconds must be a safe integer.');
  }
  if (everySeconds < kMinEveryIntervalSeconds) {
    throw const ScheduleInputException(ScheduleErrorCode.frequencyTooHigh,
        'every_seconds must be at least $kMinEveryIntervalSeconds.');
  }
  return ScheduleRecord(
    id: id,
    kind: ScheduleKind.every,
    prompt: normalized,
    everySeconds: everySeconds,
    scheduledAt: futureInstant(now.add(Duration(seconds: everySeconds)), now),
  );
}

/// 用单次墙钟采样派生一条模型可见视图。
ScheduleView scheduleView(ScheduleRecord record, DateTime now) => ScheduleView(
      record: record,
      state: now.isBefore(record.scheduledAt)
          ? ScheduleState.scheduled
          : ScheduleState.overdue,
    );
