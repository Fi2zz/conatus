/// schedule 的时间基础：四位年份 RFC 3339 UTC 的格式化、严格解析与范围校验。
///
/// 这里的函数都是纯函数，从不读取进程时区或当前时间（`now` 一律由调用方传入），
/// 因此回放与判定不依赖环境状态。
library;

import 'schedule_errors.dart';

/// 四位年份可表示范围的下界 `0001-01-01T00:00:00.000Z`。
final DateTime minFourDigitYearInstant = DateTime.utc(1);

/// 四位年份可表示范围的上界 `9999-12-31T23:59:59.999Z`。
final DateTime maxFourDigitYearInstant =
    DateTime.utc(9999, 12, 31, 23, 59, 59, 999);

/// 安全整数上界；秒数参数按它校验，避免换算毫秒时溢出。
const int kMaxSafeInteger = 9007199254740991;

/// 规范 UTC 串的形状：四位年份、毫秒固定三位、以 `Z` 结尾。
final RegExp _utcInstantPattern = RegExp(
  r'^(?!0000)\d{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])'
  r'T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d\.\d{3}Z$',
);

String _pad(int value) => value.toString().padLeft(2, '0');

/// 把时刻格式化为四位年份、毫秒固定三位的规范 UTC 串。
String formatUtcInstant(DateTime value) {
  final DateTime utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-${_pad(utc.month)}-${_pad(utc.day)}'
      'T${_pad(utc.hour)}:${_pad(utc.minute)}:${_pad(utc.second)}'
      '.${utc.millisecond.toString().padLeft(3, '0')}Z';
}

/// 判断串是否符合规范 UTC 形状（不校验历日是否真实存在）。
bool matchesUtcInstantShape(String value) => _utcInstantPattern.hasMatch(value);

/// 解析一条规范 UTC 串；形状不符或不是真实历日时返回 `null`。
///
/// 往返比对用来拒绝被自动规范化的日期（例如 `2026-02-30`）。
DateTime? tryParseUtcInstant(String value) {
  if (!_utcInstantPattern.hasMatch(value)) return null;
  final DateTime parsed = DateTime.utc(
    int.parse(value.substring(0, 4)),
    int.parse(value.substring(5, 7)),
    int.parse(value.substring(8, 10)),
    int.parse(value.substring(11, 13)),
    int.parse(value.substring(14, 16)),
    int.parse(value.substring(17, 19)),
    int.parse(value.substring(20, 23)),
  );
  return formatUtcInstant(parsed) == value ? parsed : null;
}

/// 一组精确的日历字段。
class CalendarParts {
  /// 构造一组日历字段。
  // REASON: 纯数据载体，字段即协议字段；拆成多个对象只会增加间接层。
  const CalendarParts({
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
    required this.second,
    this.millisecond = 0,
  });

  /// 四位年份。
  final int year;

  /// 月份（1—12）。
  final int month;

  /// 日（1—31）。
  final int day;

  /// 小时（0—23）。
  final int hour;

  /// 分钟（0—59）。
  final int minute;

  /// 秒（0—59）。
  final int second;

  /// 毫秒（0—999）。
  final int millisecond;

  @override
  bool operator ==(Object other) =>
      other is CalendarParts &&
      other.year == year &&
      other.month == month &&
      other.day == day &&
      other.hour == hour &&
      other.minute == minute &&
      other.second == second &&
      other.millisecond == millisecond;

  @override
  int get hashCode =>
      Object.hash(year, month, day, hour, minute, second, millisecond);
}

/// 用明确的日历字段构造 UTC 时刻；字段会被自动规范化时抛错。
DateTime calendarInstant(CalendarParts parts) {
  if (parts.year == 0 ||
      parts.year > 9999 ||
      parts.hour > 23 ||
      parts.minute > 59 ||
      parts.second > 59) {
    throw const ScheduleInputException(ScheduleErrorCode.invalidRule,
        'The at value must be a real ISO calendar date and time.');
  }
  final DateTime value = DateTime.utc(
    parts.year,
    parts.month,
    parts.day,
    parts.hour,
    parts.minute,
    parts.second,
    parts.millisecond,
  );
  final bool kept = value.year == parts.year &&
      value.month == parts.month &&
      value.day == parts.day &&
      value.hour == parts.hour &&
      value.minute == parts.minute &&
      value.second == parts.second &&
      value.millisecond == parts.millisecond;
  if (!kept) {
    throw const ScheduleInputException(ScheduleErrorCode.invalidRule,
        'The at value must be a real ISO calendar date and time.');
  }
  return value;
}

/// 校验目标严格位于未来且落在四位年份范围内，返回目标本身。
///
/// 边界含等号：`target == now` 判为 `not_future`。
DateTime futureInstant(DateTime target, DateTime now) {
  if (target.isBefore(minFourDigitYearInstant) ||
      target.isAfter(maxFourDigitYearInstant)) {
    throw const ScheduleInputException(
      ScheduleErrorCode.timeOutOfRange,
      'The scheduled time must be representable as a four-digit-year '
      'RFC 3339 UTC instant.',
    );
  }
  if (!target.isAfter(now)) {
    throw const ScheduleInputException(ScheduleErrorCode.notFuture,
        'The scheduled time must be strictly in the future.');
  }
  return target;
}

/// 判断一个秒数是否为可用的正安全整数。
bool safePositiveSeconds(Object? value) =>
    value is int && value > 0 && value <= kMaxSafeInteger;

/// 解码一个持久记录里的规范四位年份 RFC 3339 UTC 时刻。
DateTime decodeInstant(Object? value) {
  if (value is! String || !matchesUtcInstantShape(value)) {
    throw const ScheduleLogException(
        'scheduledAt must be a canonical four-digit-year RFC 3339 UTC instant');
  }
  final DateTime? parsed = tryParseUtcInstant(value);
  if (parsed == null) {
    throw const ScheduleLogException(
        'scheduledAt is not a real UTC calendar instant');
  }
  return parsed;
}
