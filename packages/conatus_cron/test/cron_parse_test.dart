import 'package:conatus_cron/conatus_cron.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('cron 字段解析', () {
    test('星号、列表、范围、步进与 Vixie a/n', () {
      expect(parseCronField('*', 0, 59), hasLength(60));
      expect(parseCronField('1,3,5', 0, 59), <int>{1, 3, 5});
      expect(parseCronField('1-5', 0, 59), <int>{1, 2, 3, 4, 5});
      expect(parseCronField('*/15', 0, 59), <int>{0, 15, 30, 45});
      expect(parseCronField('10-20/5', 0, 59), <int>{10, 15, 20});
      expect(parseCronField('5/20', 0, 59), <int>{5, 25, 45});
      expect(parseCronField('0', 0, 59), <int>{0});
    });

    test('边界与非法字段', () {
      expect(parseCronField('59', 0, 59), <int>{59});
      expect(parseCronField('60', 0, 59), isNull);
      expect(parseCronField('24', 0, 23), isNull);
      expect(parseCronField('5-2', 0, 59), isNull);
      expect(parseCronField('*/0', 0, 59), isNull);
      expect(parseCronField('1,,2', 0, 59), isNull);
      expect(parseCronField('a', 0, 59), isNull);
      expect(parseCronField('', 0, 59), isNull);
    });

    test('表达式形状与周日 7 归一', () {
      final CronExpression star = parseCronExpression('* * * * *')!;
      expect(star.domStar, isTrue);
      expect(star.dowStar, isTrue);
      expect(parseCronExpression('0 9 * * 1')!.dow, <int>{1});
      expect(parseCronExpression('0 0 * * 7')!.dow, <int>{0});
      expect(parseCronExpression('* * * *'), isNull);
      expect(parseCronExpression('* * * * * *'), isNull);
      expect(parseCronExpression('61 * * * *'), isNull);
      expect(parseCronExpression('0 0 32 * *'), isNull);
    });
  });

  group('cronMatches 的 dom-dow 语义', () {
    test('两者都受限时任一匹配，否则都匹配', () {
      final CronExpression either = parseCronExpression('0 0 13 * 5')!;
      expect(cronMatches(either, DateTime(2026, 9, 11)), isTrue);
      expect(cronMatches(either, DateTime(2026, 9, 13)), isTrue);
      expect(cronMatches(either, DateTime(2026, 9, 12)), isFalse);
      final CronExpression domOnly = parseCronExpression('0 0 13 * *')!;
      expect(cronMatches(domOnly, DateTime(2026, 9, 13)), isTrue);
      expect(cronMatches(domOnly, DateTime(2026, 9, 14)), isFalse);
    });

    test('周字段：0 是周日', () {
      final CronExpression sunday = parseCronExpression('0 0 * * 0')!;
      expect(cronMatches(sunday, DateTime(2026, 9, 13)), isTrue);
      expect(cronMatches(sunday, DateTime(2026, 9, 14)), isFalse);
    });

    test('分、时、月任一不符即不匹配', () {
      final CronExpression at = parseCronExpression('30 9 * 9 *')!;
      expect(cronMatches(at, DateTime(2026, 9, 1, 9, 30)), isTrue);
      expect(cronMatches(at, DateTime(2026, 9, 1, 9, 31)), isFalse);
      expect(cronMatches(at, DateTime(2026, 9, 1, 10, 30)), isFalse);
      expect(cronMatches(at, DateTime(2026, 10, 1, 9, 30)), isFalse);
    });
  });

  group('nextCronSlot', () {
    test('取 after 之后第一个匹配分钟', () {
      final CronExpression daily9 = parseCronExpression('0 9 * * *')!;
      final DateTime? slot = nextCronSlot(daily9, DateTime(2026, 9, 16, 8));
      expect(slot!.millisecondsSinceEpoch, epoch(DateTime(2026, 9, 16, 9)));
    });

    test('严格大于：整点时刻之后是下一天', () {
      final CronExpression daily9 = parseCronExpression('0 9 * * *')!;
      final DateTime? slot = nextCronSlot(daily9, DateTime(2026, 9, 16, 9));
      expect(slot!.millisecondsSinceEpoch, epoch(DateTime(2026, 9, 17, 9)));
    });

    test('步进与 Vixie a/n', () {
      final CronExpression quarter = parseCronExpression('*/15 * * * *')!;
      expect(
          nextCronSlot(quarter, DateTime(2026, 9, 16, 10, 7))!
              .millisecondsSinceEpoch,
          epoch(DateTime(2026, 9, 16, 10, 15)));
      final CronExpression vixie = parseCronExpression('5/20 * * * *')!;
      expect(
          nextCronSlot(vixie, DateTime(2026, 9, 16, 10, 46))!
              .millisecondsSinceEpoch,
          epoch(DateTime(2026, 9, 16, 11, 5)));
    });

    test('星期规则跳到下一个周一', () {
      final CronExpression monday = parseCronExpression('0 9 * * 1')!;
      expect(
          nextCronSlot(monday, DateTime(2026, 9, 11, 10))!
              .millisecondsSinceEpoch,
          epoch(DateTime(2026, 9, 14, 9)));
    });

    test('闰日匹配，不可能组合 4 年内返回 null', () {
      final CronExpression leap = parseCronExpression('0 0 29 2 *')!;
      expect(nextCronSlot(leap, DateTime(2026, 3, 2))!.millisecondsSinceEpoch,
          epoch(DateTime(2028, 2, 29)));
      final CronExpression impossible = parseCronExpression('0 0 30 2 *')!;
      expect(nextCronSlot(impossible, DateTime(2026, 3, 2)), isNull);
    });
  });
}
