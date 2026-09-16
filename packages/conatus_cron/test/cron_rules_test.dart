import 'package:conatus_cron/conatus_cron.dart';
import 'package:test/test.dart';

CronTask buildTask({
  String id = 'demo',
  String? at,
  num? every,
  String? daily,
  String? cron,
  bool enabled = true,
}) {
  final CronTask task = CronTask(
    id: id,
    prompt: 'ping',
    at: at,
    every: every,
    daily: daily,
    cron: cron,
    enabled: enabled,
    origin: CronTaskOrigin.dynamic,
  );
  task.cronParsed = cron == null ? null : parseCronExpression(cron);
  return task;
}

int epoch(DateTime local) => local.millisecondsSinceEpoch;

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
      final DateTime? slot =
          nextCronSlot(daily9, DateTime(2026, 9, 16, 8));
      expect(slot!.millisecondsSinceEpoch, epoch(DateTime(2026, 9, 16, 9)));
    });

    test('严格大于：整点时刻之后是下一天', () {
      final CronExpression daily9 = parseCronExpression('0 9 * * *')!;
      final DateTime? slot =
          nextCronSlot(daily9, DateTime(2026, 9, 16, 9));
      expect(slot!.millisecondsSinceEpoch, epoch(DateTime(2026, 9, 17, 9)));
    });

    test('步进与 Vixie a/n', () {
      final CronExpression quarter = parseCronExpression('*/15 * * * *')!;
      expect(nextCronSlot(quarter, DateTime(2026, 9, 16, 10, 7))!.millisecondsSinceEpoch,
          epoch(DateTime(2026, 9, 16, 10, 15)));
      final CronExpression vixie = parseCronExpression('5/20 * * * *')!;
      expect(nextCronSlot(vixie, DateTime(2026, 9, 16, 10, 46))!.millisecondsSinceEpoch,
          epoch(DateTime(2026, 9, 16, 11, 5)));
    });

    test('星期规则跳到下一个周一', () {
      final CronExpression monday = parseCronExpression('0 9 * * 1')!;
      expect(nextCronSlot(monday, DateTime(2026, 9, 11, 10))!.millisecondsSinceEpoch,
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

  group('dueSlot 规则语义', () {
    test('at：到期触发一次，消费后不再触发', () {
      final CronTask task = buildTask(at: '2026-09-15T16:00:00+08:00');
      final DateTime now = DateTime(2026, 9, 16, 10);
      expect(dueSlot(task, now, now), isNotNull);
      task.firedAt = now;
      expect(dueSlot(task, now, now), isNull);
      final CronTask future = buildTask(at: '2026-09-16T23:00:00+08:00');
      expect(dueSlot(future, now, now), isNull);
    });

    test('every：锚定 lastRunAt ?? startedAt', () {
      final DateTime startedAt = DateTime(2026, 9, 16, 10);
      final CronTask task = buildTask(every: 600);
      expect(dueSlot(task, startedAt.add(const Duration(seconds: 599)), startedAt), isNull);
      final DateTime? slot =
          dueSlot(task, startedAt.add(const Duration(seconds: 600)), startedAt);
      expect(slot!.millisecondsSinceEpoch,
          epoch(startedAt.add(const Duration(seconds: 600))));
      task.lastRunAt = startedAt.add(const Duration(seconds: 600));
      expect(dueSlot(task, startedAt.add(const Duration(seconds: 1199)), startedAt), isNull);
      expect(dueSlot(task, startedAt.add(const Duration(seconds: 1200)), startedAt), isNotNull);
    });

    test('daily：错过当天时段补发一次', () {
      final DateTime now = DateTime(2026, 9, 16, 10);
      final CronTask task = buildTask(daily: '09:00');
      expect(dueSlot(task, now, now)!.millisecondsSinceEpoch,
          epoch(DateTime(2026, 9, 16, 9)));
      expect(dueSlot(task, DateTime(2026, 9, 16, 8), DateTime(2026, 9, 16, 8)), isNull);
      task.lastRunAt = DateTime(2026, 9, 16, 9);
      expect(dueSlot(task, now, now), isNull);
      task.lastRunAt = DateTime(2026, 9, 15, 9);
      expect(dueSlot(task, now, now), isNotNull);
    });

    test('cron：用缓存的下一个时段，触发后失效重算', () {
      final DateTime startedAt = DateTime(2026, 9, 16, 8);
      final CronTask task = buildTask(cron: '0 9 * * *');
      expect(dueSlot(task, DateTime(2026, 9, 16, 8, 30), startedAt), isNull);
      final DateTime? slot = dueSlot(task, DateTime(2026, 9, 16, 9, 30), startedAt);
      expect(slot!.millisecondsSinceEpoch, epoch(DateTime(2026, 9, 16, 9)));
      expect(task.cronNext, isNotNull);
      task.lastRunAt = DateTime(2026, 9, 16, 9, 30);
      task.cronNext = null;
      expect(dueSlot(task, DateTime(2026, 9, 16, 9, 31), startedAt), isNull);
    });

    test('停用的任务一律不触发，覆盖优先于声明值', () {
      final DateTime now = DateTime(2026, 9, 16, 10);
      final CronTask disabled = buildTask(daily: '09:00', enabled: false);
      expect(dueSlot(disabled, now, now), isNull);
      disabled.enabledOverride = true;
      expect(dueSlot(disabled, now, now), isNotNull);
      final CronTask declared = buildTask(daily: '09:00');
      declared.enabledOverride = false;
      expect(taskEnabled(declared), isFalse);
      expect(nextRunAtOf(declared, now, now), isNull);
    });
  });

  group('nextRunAtOf 列表展示', () {
    test('at / every / daily / cron 的下一次触发', () {
      final DateTime startedAt = DateTime(2026, 9, 16, 8);
      final DateTime now = DateTime(2026, 9, 16, 10);
      final CronTask at = buildTask(at: '2026-09-16T12:00:00+08:00');
      expect(nextRunAtOf(at, now, startedAt), isNotNull);
      at.firedAt = now;
      expect(nextRunAtOf(at, now, startedAt), isNull);
      final CronTask every = buildTask(every: 600);
      expect(nextRunAtOf(every, now, startedAt)!.millisecondsSinceEpoch,
          epoch(startedAt.add(const Duration(seconds: 600))));
      final CronTask daily = buildTask(daily: '11:00');
      expect(nextRunAtOf(daily, now, startedAt)!.millisecondsSinceEpoch,
          epoch(DateTime(2026, 9, 16, 11)));
      final CronTask cron = buildTask(cron: '0 9 * * *');
      expect(nextRunAtOf(cron, now, startedAt)!.millisecondsSinceEpoch,
          epoch(DateTime(2026, 9, 16, 9)),
          reason: 'cron 返回缓存的下一时段，即使已略过（与 dsh-cron 一致）');
    });

    test('daily 错过未补发时仍显示今天，已消费显示明天', () {
      final DateTime now = DateTime(2026, 9, 16, 10);
      final CronTask missed = buildTask(daily: '09:00');
      expect(nextRunAtOf(missed, now, now)!.millisecondsSinceEpoch,
          epoch(DateTime(2026, 9, 16, 9)));
      final CronTask consumed = buildTask(daily: '09:00');
      consumed.lastRunAt = DateTime(2026, 9, 16, 9);
      expect(nextRunAtOf(consumed, now, now)!.millisecondsSinceEpoch,
          epoch(DateTime(2026, 9, 17, 9)));
    });
  });

  group('输入校验', () {
    CronTaskInput input({
      Object? id = 'demo',
      Object? prompt = 'ping',
      Object? at,
      Object? every,
      Object? daily,
      Object? cron,
    }) =>
        (
          id: id,
          prompt: prompt,
          at: at,
          every: every,
          daily: daily,
          cron: cron,
        );

    test('四种规则各自合法', () {
      expect(validateTaskInput(input(at: '2026-09-16T09:00:00+08:00')), isNull);
      expect(validateTaskInput(input(every: 10)), isNull);
      expect(validateTaskInput(input(daily: '09:30')), isNull);
      expect(validateTaskInput(input(cron: '0 9 * * *')), isNull);
    });

    test('id / prompt / 规则数量', () {
      expect(validateTaskInput(input(id: 'x y', every: 60)),
          contains('invalid task id'));
      expect(validateTaskInput(input(id: '-abc', every: 60)),
          contains('invalid task id'));
      expect(validateTaskInput(input(id: 'x' * 65, every: 60)),
          contains('invalid task id'));
      expect(validateTaskInput(input(id: 7, every: 60)), contains('invalid task id'));
      expect(validateTaskInput(input(prompt: '   ', every: 60)),
          contains('needs a non-empty prompt'));
      expect(validateTaskInput(input(every: 60, daily: '09:00')),
          contains('exactly one'));
      expect(validateTaskInput(input()), contains('exactly one'));
    });

    test('规则取值校验', () {
      expect(validateTaskInput(input(at: 'not-a-date')), contains('unparseable at value'));
      expect(validateTaskInput(input(every: 5)), contains('every must be a number >= 10'));
      expect(validateTaskInput(input(every: 'abc')), contains('every must be a number >= 10'));
      expect(validateTaskInput(input(daily: '9:00')), contains('daily must be "HH:MM" (24h)'));
      expect(validateTaskInput(input(daily: '24:00')), contains('daily must be "HH:MM" (24h)'));
      expect(validateTaskInput(input(cron: 'bad')), contains('invalid cron expression'));
    });
  });

  group('framing 与 id 生成', () {
    test('触发消息逐行保留 dsh-cron 原文案', () {
      final String message = renderTaskMessage(
        id: 'demo',
        prompt: 'hello',
        slot: DateTime.utc(2026, 9, 16, 1),
        firedAt: DateTime.utc(2026, 9, 16, 2, 30),
      );
      expect(message, <String>[
        '[cron] Scheduled task "demo" fired.',
        'Scheduled for: 2026-09-16T01:00:00.000Z',
        'Fired at: 2026-09-16T02:30:00.000Z',
        '',
        'This is an automated task submitted by the cron plugin, '
            'not a message from the user.',
        'Execute the task inside <task> now, then report the result concisely.',
        '',
        '<task>',
        'hello',
        '</task>',
      ].join('\n'));
    });

    test('任务 id：base36 毫秒 + base36 随机后缀', () {
      final String id = generateTaskId(DateTime.utc(2026, 9, 16), 12345);
      expect(kCronTaskIdPattern.hasMatch(id), isTrue);
      expect(id.endsWith('-09ix'), isTrue);
      expect(generateTaskId(DateTime.utc(2026, 9, 16), 1), isNot(id));
    });
  });
}
