/// `at` 选择器的解析：显式偏移的 RFC 3339 串，或带 IANA 时区的本地日历对象。
///
/// 提交的偏移量与本地字段都不会进入持久记录，只有规范化后的 UTC 瞬时会被保留。
/// 本地时刻到瞬时的换算（含夏令时缺口与重叠规则）见 `schedule_local_instant.dart`。
library;

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'schedule_errors.dart';
import 'schedule_local_instant.dart';
import 'schedule_time.dart';

bool _timeZoneDataLoaded = false;

/// 惰性装载 IANA 时区数据库（幂等）。
void loadTimeZoneData() {
  if (_timeZoneDataLoaded) return;
  tzdata.initializeTimeZones();
  _timeZoneDataLoaded = true;
}

final RegExp _offsetInstantPattern = RegExp(
  r'^(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})'
  r'T(?<hour>\d{2}):(?<minute>\d{2}):(?<second>\d{2})'
  r'(?:\.(?<fraction>\d{1,3}))?'
  r'(?<zone>Z|(?<sign>[+-])(?<offsetHour>\d{2}):(?<offsetMinute>\d{2}))$',
);

final RegExp _localDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

final RegExp _localTimePattern =
    RegExp(r'^(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?$');

final RegExp _ianaZonePattern =
    RegExp(r'^[A-Za-z][A-Za-z0-9_+.-]*(?:/[A-Za-z0-9_+.-]+)+$');

/// 解析 `schedule_create` 的 `at` 选择器，返回目标时刻。
DateTime resolveAtTarget(Object? value) {
  if (value is String) return parseOffsetInstant(value);
  if (value is Map) return resolveLocalAt(value);
  throw const ScheduleInputException(
    ScheduleErrorCode.invalidRule,
    'at must be an explicit-offset string or local calendar object.',
  );
}

/// 解析严格偏移形态：偏移量是输入的一部分，缺省 `Z` 或偏移会被拒绝。
DateTime parseOffsetInstant(String value) {
  final RegExpMatch? match = _offsetInstantPattern.firstMatch(value);
  if (match == null) {
    throw const ScheduleInputException(
      ScheduleErrorCode.invalidRule,
      'at must use YYYY-MM-DDTHH:mm:ss with optional 1-3 digit fractional '
      'seconds and an explicit Z or numeric offset.',
    );
  }
  final DateTime localEpoch = calendarInstant(CalendarParts(
    year: int.parse(match.namedGroup('year')!),
    month: int.parse(match.namedGroup('month')!),
    day: int.parse(match.namedGroup('day')!),
    hour: int.parse(match.namedGroup('hour')!),
    minute: int.parse(match.namedGroup('minute')!),
    second: int.parse(match.namedGroup('second')!),
    millisecond: _fractionMilliseconds(match.namedGroup('fraction')),
  ));
  if (match.namedGroup('zone') == 'Z') return localEpoch;
  final int offsetHour = int.parse(match.namedGroup('offsetHour')!);
  final int offsetMinute = int.parse(match.namedGroup('offsetMinute')!);
  final bool negativeZero =
      match.namedGroup('sign') == '-' && offsetHour == 0 && offsetMinute == 0;
  if (offsetHour > 23 || offsetMinute > 59 || negativeZero) {
    throw const ScheduleInputException(
        ScheduleErrorCode.invalidRule, 'The at numeric offset is invalid.');
  }
  final int minutes = offsetHour * 60 + offsetMinute;
  return match.namedGroup('sign') == '+'
      ? localEpoch.subtract(Duration(minutes: minutes))
      : localEpoch.add(Duration(minutes: minutes));
}

/// 解析本地日历对象形态：`date` / `time` / `time_zone` 三键缺一不可。
DateTime resolveLocalAt(Map<Object?, Object?> value) {
  if (!_exactKeys(value, const <String>['date', 'time', 'time_zone'])) {
    throw const ScheduleInputException(ScheduleErrorCode.invalidRule,
        'Local at must contain exactly date, time, and time_zone.');
  }
  final Object? date = value['date'];
  final Object? time = value['time'];
  if (date is! String || time is! String) {
    throw const ScheduleInputException(ScheduleErrorCode.invalidRule,
        'Local at date and time must be strings.');
  }
  final Object? zone = value['time_zone'];
  if (zone is! String) {
    throw const ScheduleInputException(
        ScheduleErrorCode.invalidTimeZone, 'time_zone must be a string.');
  }
  return resolveLocalInstant(
      parseLocalParts(date, time), canonicalTimeZone(zone));
}

/// 解析 `date` 与 `time` 字段；任一项非法即拒绝。
CalendarParts parseLocalParts(String date, String time) {
  final RegExpMatch? dateMatch = _localDatePattern.firstMatch(date);
  final RegExpMatch? timeMatch = _localTimePattern.firstMatch(time);
  if (dateMatch == null || timeMatch == null) {
    throw const ScheduleInputException(
      ScheduleErrorCode.invalidRule,
      'Local at requires date YYYY-MM-DD and time HH:mm:ss with optional '
      'one-to-three digit milliseconds.',
    );
  }
  final CalendarParts parts = CalendarParts(
    year: int.parse(dateMatch.group(1)!),
    month: int.parse(dateMatch.group(2)!),
    day: int.parse(dateMatch.group(3)!),
    hour: int.parse(timeMatch.group(1)!),
    minute: int.parse(timeMatch.group(2)!),
    second: int.parse(timeMatch.group(3)!),
    millisecond: _fractionMilliseconds(timeMatch.group(4)),
  );
  calendarInstant(parts);
  return parts;
}

/// 校验并解析一个 `UTC` 或 IANA `Area/Location` 时区名。
tz.Location canonicalTimeZone(String value) {
  final bool shaped = value == 'UTC' || _ianaZonePattern.hasMatch(value);
  if (value.isEmpty || value.trim() != value || !shaped) {
    throw const ScheduleInputException(ScheduleErrorCode.invalidTimeZone,
        'time_zone must be UTC or a valid IANA Area/Location name.');
  }
  loadTimeZoneData();
  try {
    return tz.getLocation(value);
  } on Exception {
    throw const ScheduleInputException(ScheduleErrorCode.invalidTimeZone,
        'time_zone must be UTC or a valid IANA Area/Location name.');
  }
}

int _fractionMilliseconds(String? fraction) =>
    fraction == null ? 0 : int.parse(fraction.padRight(3, '0'));

bool _exactKeys(Map<Object?, Object?> value, List<String> expected) {
  if (value.length != expected.length) return false;
  for (final String key in expected) {
    if (!value.containsKey(key)) return false;
  }
  return true;
}
