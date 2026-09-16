import 'package:conatus_schedule/conatus_schedule.dart';
import 'package:test/test.dart';

Matcher inputError(String code) => throwsA(isA<ScheduleInputException>()
    .having((ScheduleInputException error) => error.code, 'code', code));

void main() {
  group('规范 UTC 串', () {
    test('格式化与解析往返', () {
      final DateTime instant = DateTime.utc(2026, 8, 6, 12, 0, 0, 5);
      expect(formatUtcInstant(instant), '2026-08-06T12:00:00.005Z');
      expect(tryParseUtcInstant('2026-08-06T12:00:00.005Z'), instant);
    });

    test('拒绝非规范形状与非真实历日', () {
      expect(tryParseUtcInstant('2026-02-30T00:00:00.000Z'), isNull);
      expect(tryParseUtcInstant('2026-08-06T12:00:00Z'), isNull);
      expect(matchesUtcInstantShape('10000-01-01T00:00:00.000Z'), isFalse);
      expect(matchesUtcInstantShape('0000-01-01T00:00:00.000Z'), isFalse);
    });
  });

  group('at 偏移串', () {
    test('偏移是输入的一部分', () {
      expect(parseOffsetInstant('2026-08-06T12:00:00+08:00'),
          DateTime.utc(2026, 8, 6, 4));
      expect(parseOffsetInstant('2026-08-06T12:00:00-05:30'),
          DateTime.utc(2026, 8, 6, 17, 30));
      expect(parseOffsetInstant('2026-08-06T12:00:00.1Z'),
          DateTime.utc(2026, 8, 6, 12, 0, 0, 100));
      expect(parseOffsetInstant('2026-08-06T12:00:00+00:00'),
          DateTime.utc(2026, 8, 6, 12));
    });

    test('缺偏移、非法历日与非法偏移被拒绝', () {
      final List<String> bad = <String>[
        '2026-08-06T12:00:00',
        '2026-08-06 12:00:00Z',
        '2026-02-30T12:00:00Z',
        '0000-08-06T12:00:00Z',
        '2026-08-06T24:00:00Z',
        '2026-08-06T12:00:00-00:00',
        '2026-08-06T12:00:00+24:00',
      ];
      for (final String value in bad) {
        expect(() => parseOffsetInstant(value),
            inputError(ScheduleErrorCode.invalidRule),
            reason: value);
      }
    });
  });

  group('at 本地对象', () {
    test('UTC 与 Asia/Shanghai 换算为 UTC 瞬时', () {
      expect(
        resolveAtTarget(<String, Object?>{
          'date': '2026-08-06',
          'time': '12:00:00',
          'time_zone': 'UTC',
        }),
        DateTime.utc(2026, 8, 6, 12),
      );
      expect(
        resolveAtTarget(<String, Object?>{
          'date': '2026-08-06',
          'time': '12:00:00',
          'time_zone': 'Asia/Shanghai',
        }),
        DateTime.utc(2026, 8, 6, 4),
      );
    });

    test('夏令时重叠取较早的瞬时', () {
      expect(
        resolveAtTarget(<String, Object?>{
          'date': '2026-11-01',
          'time': '01:30:00',
          'time_zone': 'America/New_York',
        }),
        DateTime.utc(2026, 11, 1, 5, 30),
      );
    });

    test('夏令时缺口内的本地时刻被拒绝', () {
      expect(
        () => resolveAtTarget(<String, Object?>{
          'date': '2026-03-08',
          'time': '02:30:00',
          'time_zone': 'America/New_York',
        }),
        inputError(ScheduleErrorCode.invalidRule),
      );
    });

    test('时区名必须是 UTC 或 IANA Area/Location', () {
      final List<String> bad = <String>[
        'CST',
        'GMT',
        '+08:00',
        '',
        ' Asia/Shanghai',
        'Nope/Nowhere',
      ];
      for (final String zone in bad) {
        expect(() => canonicalTimeZone(zone),
            inputError(ScheduleErrorCode.invalidTimeZone),
            reason: zone);
      }
      expect(canonicalTimeZone('Asia/Shanghai').name, 'Asia/Shanghai');
    });

    test('本地选择器形状违规被拒绝', () {
      final List<Map<String, Object?>> bad = <Map<String, Object?>>[
        <String, Object?>{'date': '2026-08-06', 'time': '12:00:00'},
        <String, Object?>{
          'date': '2026-08-06',
          'time': '12:00:00',
          'time_zone': 'UTC',
          'extra': 1,
        },
        <String, Object?>{
          'date': '2026-8-6',
          'time': '12:00:00',
          'time_zone': 'UTC'
        },
        <String, Object?>{
          'date': '2026-02-30',
          'time': '12:00:00',
          'time_zone': 'UTC'
        },
      ];
      for (final Map<String, Object?> value in bad) {
        expect(() => resolveAtTarget(value),
            throwsA(isA<ScheduleInputException>()),
            reason: '$value');
      }
    });
  });

  group('未来与范围校验', () {
    test('边界含等号', () {
      final DateTime now = DateTime.utc(2026, 8, 6, 12);
      expect(futureInstant(DateTime.utc(2026, 8, 6, 12, 0, 0, 1), now),
          DateTime.utc(2026, 8, 6, 12, 0, 0, 1));
      expect(() => futureInstant(now, now),
          inputError(ScheduleErrorCode.notFuture));
    });

    test('超出四位年份范围', () {
      expect(
        () => futureInstant(DateTime.utc(10000), DateTime.utc(2026, 8, 6, 12)),
        inputError(ScheduleErrorCode.timeOutOfRange),
      );
    });
  });

  group('创建规则', () {
    test('延迟与固定间隔计算目标时刻', () {
      final DateTime now = DateTime.utc(2026, 8, 6, 12);
      expect(
        createAfterRecord(id: 'a', prompt: ' 提醒 ', afterSeconds: 600, now: now)
            .scheduledAt,
        DateTime.utc(2026, 8, 6, 12, 10),
      );
      expect(
        createEveryRecord(id: 'b', prompt: '提醒', everySeconds: 300, now: now)
            .scheduledAt,
        DateTime.utc(2026, 8, 6, 12, 5),
      );
      expect(
        createAfterRecord(id: 'a', prompt: ' 提醒 ', afterSeconds: 600, now: now)
            .prompt,
        '提醒',
      );
    });

    test('空内容与非法间隔的错误码', () {
      final DateTime now = DateTime.utc(2026, 8, 6, 12);
      expect(
        () => createAfterRecord(
            id: 'a', prompt: '   ', afterSeconds: 60, now: now),
        inputError(ScheduleErrorCode.invalidPrompt),
      );
      expect(
        () =>
            createAfterRecord(id: 'a', prompt: 'p', afterSeconds: 0, now: now),
        inputError(ScheduleErrorCode.invalidRule),
      );
      expect(
        () => createEveryRecord(
            id: 'a', prompt: 'p', everySeconds: 299, now: now),
        inputError(ScheduleErrorCode.frequencyTooHigh),
      );
    });

    test('视图状态边界含等号', () {
      final ScheduleRecord record = createAfterRecord(
          id: 'a',
          prompt: 'p',
          afterSeconds: 60,
          now: DateTime.utc(2026, 8, 6, 12));
      expect(scheduleView(record, DateTime.utc(2026, 8, 6, 12, 0, 59)).state,
          ScheduleState.scheduled);
      expect(scheduleView(record, DateTime.utc(2026, 8, 6, 12, 1)).state,
          ScheduleState.overdue);
      expect(
          scheduleView(record, DateTime.utc(2026, 8, 6, 12, 1))
              .toJson()['deliveryMode'],
          kScheduleDeliveryMode);
    });
  });
}
