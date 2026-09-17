/// 任务规则：输入校验、到期判定、下次触发时刻与调度谓词。
///
/// 这里全部是纯函数：now / startedAt / firedAt 一律由调用方传入，不读墙钟，
/// 保证可测与回放。错误消息与 dsh-cron 保持一致（工具结果直接透出）。
library;

import 'dart:convert';

import 'cron_parse.dart';
import 'cron_types.dart';

/// 调度规则键；patch 命中任何一个都视为改动排期。
const List<String> kCronRuleKeys = <String>['at', 'every', 'daily', 'cron'];

/// 任务输入的原始形状：id + prompt + 四选一规则（未经校验的原始值）。
typedef CronTaskInput = ({
  Object? id,
  Object? prompt,
  Object? at,
  Object? every,
  Object? daily,
  Object? cron,
});

/// 校验任务输入；返回错误消息或 null。
String? validateTaskInput(CronTaskInput input) {
  final String? idError = _validateId(input.id);
  if (idError != null) return idError;
  final String? shapeError = _validateShape(input);
  if (shapeError != null) return shapeError;
  return _validateAt(input.id, input.at) ??
      _validateEvery(input.id, input.every) ??
      _validateDaily(input.id, input.daily) ??
      _validateCron(input.id, input.cron);
}

String? _validateId(Object? id) {
  final bool shapeOk = id is String && kCronTaskIdPattern.hasMatch(id);
  if (!shapeOk) return 'invalid task id: ${_describeValue(id)}';
  return null;
}

String _describeValue(Object? value) =>
    value is String ? jsonEncode(value) : '$value';

String? _validateShape(CronTaskInput input) {
  final Object? prompt = input.prompt;
  final bool promptOk = prompt is String && prompt.trim().isNotEmpty;
  if (!promptOk) return 'task "${input.id}" needs a non-empty prompt';
  final int rules = <bool>[
    _jsTruthy(input.at),
    input.every != null,
    _jsTruthy(input.daily),
    _jsTruthy(input.cron),
  ].where((bool active) => active).length;
  if (rules != 1) {
    return 'task "${input.id}" must set exactly one of at / every / daily / cron';
  }
  return null;
}

String? _validateAt(Object? id, Object? at) {
  if (!_jsTruthy(at)) return null;
  final DateTime? instant = at is String ? DateTime.tryParse(at) : null;
  if (instant == null) return 'task "$id" has an unparseable at value';
  return null;
}

String? _validateEvery(Object? id, Object? every) {
  if (every == null) return null;
  final bool valid =
      every is num && every.isFinite && every >= kCronMinEverySeconds;
  if (!valid) {
    return 'task "$id" every must be a number >= $kCronMinEverySeconds';
  }
  return null;
}

String? _validateDaily(Object? id, Object? daily) {
  if (!_jsTruthy(daily)) return null;
  final bool valid = daily is String && kCronDailyPattern.hasMatch(daily);
  if (!valid) return 'task "$id" daily must be "HH:MM" (24h)';
  return null;
}

String? _validateCron(Object? id, Object? cron) {
  if (!_jsTruthy(cron)) return null;
  final bool valid = cron is String && parseCronExpression(cron) != null;
  if (!valid) {
    return 'task "$id" has an invalid cron expression '
        '(want 5 fields: minute hour day month weekday)';
  }
  return null;
}

/// dsh-cron 的真值判断：规则计数对 at / daily / cron 用真值，对 every 用非空。
bool _jsTruthy(Object? value) {
  if (value == null || value is bool) return value == true;
  if (value is num) return value != 0 && !value.isNaN;
  if (value is String) return value.isNotEmpty;
  return true;
}

/// 任务当前生效的规则种类（校验保证恰好一个）。
CronRuleKind taskRuleKind(CronTask task) {
  if (task.at != null) return CronRuleKind.at;
  if (task.every != null) return CronRuleKind.every;
  if (task.daily != null) return CronRuleKind.daily;
  return CronRuleKind.cron;
}

/// 生效的启停值：运行时覆盖优先于声明值。
bool taskEnabled(CronTask task) => task.enabledOverride ?? task.enabled;

/// 今天本地时间 daily 规则对应的时刻（可早于 now）。
DateTime? dailySlot(String daily, DateTime now) {
  final RegExpMatch? match = kCronDailyPattern.firstMatch(daily);
  if (match == null) return null;
  final DateTime local = now.toLocal();
  return DateTime(local.year, local.month, local.day, int.parse(match[1]!),
      int.parse(match[2]!));
}

/// 缓存的下一个 cron 触发分钟；缓存 miss 时按锚点重算并写回。
DateTime? cronNextOf(CronTask task, DateTime startedAt) {
  final DateTime? cached = task.cronNext;
  if (cached != null) return cached;
  final DateTime anchor =
      task.lastRunAt ?? startedAt.subtract(const Duration(minutes: 1));
  final DateTime? next = nextCronSlot(task.cronParsed!, anchor);
  task.cronNext = next;
  return next;
}

/// 任务此刻到期的时段；未到期、已消费或停用时返回 null。
DateTime? dueSlot(CronTask task, DateTime now, DateTime startedAt) {
  if (!taskEnabled(task)) return null;
  return switch (taskRuleKind(task)) {
    CronRuleKind.at => _atDueSlot(task, now),
    CronRuleKind.every => _everyDueSlot(task, now, startedAt),
    CronRuleKind.daily => _dailyDueSlot(task, now),
    CronRuleKind.cron => _cronDueSlot(task, now, startedAt),
  };
}

DateTime? _atDueSlot(CronTask task, DateTime now) {
  if (task.firedAt != null) return null;
  final DateTime? instant = DateTime.tryParse(task.at!);
  if (instant == null) return null;
  return now.isBefore(instant) ? null : instant;
}

DateTime? _everyDueSlot(CronTask task, DateTime now, DateTime startedAt) {
  final DateTime slot =
      (task.lastRunAt ?? startedAt).add(_everyInterval(task.every!));
  return now.isBefore(slot) ? null : slot;
}

DateTime? _dailyDueSlot(CronTask task, DateTime now) {
  final DateTime? slot = dailySlot(task.daily!, now);
  if (slot == null || slot.isAfter(now)) return null;
  final DateTime? last = task.lastRunAt;
  if (last != null && !last.isBefore(slot)) return null;
  return slot;
}

DateTime? _cronDueSlot(CronTask task, DateTime now, DateTime startedAt) {
  final DateTime? slot = cronNextOf(task, startedAt);
  if (slot == null || now.isBefore(slot)) return null;
  return slot;
}

/// 列表展示用的下一次触发时刻；停用或一次性已消费返回 null。
DateTime? nextRunAtOf(CronTask task, DateTime now, DateTime startedAt) {
  if (!taskEnabled(task)) return null;
  return switch (taskRuleKind(task)) {
    CronRuleKind.at =>
      task.firedAt != null ? null : DateTime.tryParse(task.at!),
    CronRuleKind.every =>
      (task.lastRunAt ?? startedAt).add(_everyInterval(task.every!)),
    CronRuleKind.daily => _dailyNextRun(task, now),
    CronRuleKind.cron => cronNextOf(task, startedAt),
  };
}

DateTime? _dailyNextRun(CronTask task, DateTime now) {
  final DateTime? slot = dailySlot(task.daily!, now);
  if (slot == null || slot.isAfter(now)) return slot;
  final DateTime? last = task.lastRunAt;
  if (last == null || last.isBefore(slot)) return slot;
  return slot.add(const Duration(days: 1));
}

Duration _everyInterval(num seconds) =>
    Duration(milliseconds: (seconds * 1000).round());

/// 生成一个任务 id：时间有序 base36 毫秒 + base36 随机后缀（4 位）。
String generateTaskId(DateTime now, int randomSuffix) =>
    'task-${now.millisecondsSinceEpoch.toRadixString(36)}-'
    '${randomSuffix.toRadixString(36).padLeft(4, '0')}';
