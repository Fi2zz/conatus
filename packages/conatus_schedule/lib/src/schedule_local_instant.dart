/// 本地墙钟读数到 UTC 瞬时的换算。
///
/// 规则与协议一致：夏令时缺口内的本地时刻不存在，直接拒绝；重叠（同一读数出现
/// 两次）时取较早的那个瞬时。实现方式是采样前后两天内的可用偏移量，逐个回投射
/// 校验字段是否确实还原，因此不依赖任何进程级时区设置。
library;

import 'package:timezone/timezone.dart' as tz;

import 'schedule_errors.dart';
import 'schedule_time.dart';

const List<int> _samplingDeltas = <int>[
  -172800000,
  -86400000,
  0,
  86400000,
  172800000,
];

final int _minMillis = minFourDigitYearInstant.millisecondsSinceEpoch;
final int _maxMillis = maxFourDigitYearInstant.millisecondsSinceEpoch;

/// 把本地墙钟读数解析为瞬时：重叠取较早，缺口拒绝。
DateTime resolveLocalInstant(CalendarParts parts, tz.Location location) {
  final int localMillis = calendarInstant(parts).millisecondsSinceEpoch;
  final Set<int> offsets = <int>{};
  for (final int delta in _samplingDeltas) {
    offsets.add(_project(_clampToRange(localMillis + delta), location).offset);
  }
  final List<int> candidates = <int>[];
  bool outOfRange = false;
  for (final int offset in offsets) {
    final int candidate = localMillis - offset;
    if (candidate < _minMillis || candidate > _maxMillis) {
      outOfRange = true;
      continue;
    }
    if (_project(candidate, location).parts == parts) candidates.add(candidate);
  }
  candidates.sort();
  if (candidates.isEmpty) {
    if (outOfRange) {
      throw const ScheduleInputException(
        ScheduleErrorCode.timeOutOfRange,
        'The scheduled time must be representable as a four-digit-year '
        'RFC 3339 UTC instant.',
      );
    }
    throw const ScheduleInputException(
      ScheduleErrorCode.invalidRule,
      'The local at time does not exist in the selected time zone.',
    );
  }
  return DateTime.fromMillisecondsSinceEpoch(candidates.first, isUtc: true);
}

int _clampToRange(int millis) {
  if (millis < _minMillis) return _minMillis;
  if (millis > _maxMillis) return _maxMillis;
  return millis;
}

({CalendarParts parts, int offset}) _project(int millis, tz.Location location) {
  final tz.TZDateTime value =
      tz.TZDateTime.fromMillisecondsSinceEpoch(location, millis);
  return (
    parts: CalendarParts(
      year: value.year,
      month: value.month,
      day: value.day,
      hour: value.hour,
      minute: value.minute,
      second: value.second,
      millisecond: value.millisecond,
    ),
    offset: value.timeZoneOffset.inMilliseconds,
  );
}
