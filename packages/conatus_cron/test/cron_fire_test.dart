import 'package:conatus_cron/conatus_cron.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('到期任务触发：写运行戳与 delivered 历史，不重复触发', () async {
    DateTime now = base;
    final Harness harness = Harness(clock: () => now);
    harness.service.addDynamicTask(
        <String, Object?>{'id': 'demo', 'prompt': 'ping', 'every': 600});
    final CronRuntime runtime = CronRuntime(
      service: harness.service,
      deliver: harness.accept,
      options: CronRuntimeOptions(
        clock: () => now,
        tickSeconds: 3600,
        firstTickDelay: const Duration(hours: 1),
      ),
    );
    addTearDown(runtime.dispose);

    await runtime.tick();
    expect(harness.delivered, isEmpty, reason: '未到 600 秒');

    now = base.add(const Duration(seconds: 601));
    await runtime.tick();
    expect(harness.delivered, hasLength(1));
    expect(harness.delivered.single,
        contains('[cron] Scheduled task "demo" fired.'));
    expect(harness.delivered.single, contains('<task>\nping\n</task>'));
    expect(harness.tasks.single.id, 'demo',
        reason: 'deliver 携带原始任务，调用方可自行渲染');

    final CronTask task = harness.service.findTask('demo')!;
    expect(task.lastRunAt!.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
    final List<CronRunRecord> history = harness.service.listHistory();
    expect(history.single.status, CronRunStatus.delivered);
    expect(history.single.taskId, 'demo');
    expect(history.single.scheduledFor.millisecondsSinceEpoch,
        base.add(const Duration(seconds: 600)).millisecondsSinceEpoch);

    await runtime.tick();
    expect(harness.delivered, hasLength(1), reason: '槽位已消费，不重复触发');
  });

  test('deliver 返回 false 不消费槽位，下个 tick 重试', () async {
    DateTime now = base;
    var refusals = 0;
    final Harness harness = Harness(
      clock: () => now,
      deliver: (String framing) => ++refusals > 2,
    );
    harness.service.addDynamicTask(
        <String, Object?>{'id': 'demo', 'prompt': 'ping', 'every': 600});
    final CronRuntime runtime = CronRuntime(
      service: harness.service,
      deliver: harness.accept,
      options: CronRuntimeOptions(
        clock: () => now,
        tickSeconds: 3600,
        firstTickDelay: const Duration(hours: 1),
      ),
    );
    addTearDown(runtime.dispose);

    now = base.add(const Duration(seconds: 601));
    await runtime.tick();
    expect(harness.delivered, hasLength(1), reason: '被拒也先调用了 deliver');
    expect(harness.service.listHistory(), isEmpty);
    expect(harness.service.findTask('demo')!.lastRunAt, isNull);
    expect(harness.warnings.join('\n'), contains('delivery was refused'));

    await runtime.tick();
    expect(harness.service.listHistory(), isEmpty, reason: '第二次仍被拒，槽位保持未消费');
    expect(harness.service.findTask('demo')!.lastRunAt, isNull);

    await runtime.tick();
    expect(harness.service.listHistory(), hasLength(1),
        reason: '第三次 deliver 放行后消费槽位');
    expect(harness.service.findTask('demo')!.lastRunAt, isNotNull);
    expect(harness.records.toSet(), hasLength(1),
        reason: '被拒后 seq 归还，同一时段重试复用同一 recordId');
  });

  test('deliver 抛错视同拒绝：告警且不重试消费', () async {
    DateTime now = base;
    final Harness harness = Harness(clock: () => now);
    harness.service.addDynamicTask(
        <String, Object?>{'id': 'demo', 'prompt': 'ping', 'every': 600});
    final CronRuntime runtime = CronRuntime(
      service: harness.service,
      deliver: (String recordId, String framing, CronTask task) async =>
          throw StateError('session busy'),
      options: CronRuntimeOptions(
        clock: () => now,
        tickSeconds: 3600,
        firstTickDelay: const Duration(hours: 1),
      ),
    );
    addTearDown(runtime.dispose);

    now = base.add(const Duration(seconds: 601));
    await runtime.tick();
    expect(harness.warnings.join('\n'), contains('deliver failed'));
    expect(harness.service.listHistory(), isEmpty);
    expect(harness.service.findTask('demo')!.lastRunAt, isNull);
  });

  test('单任务故障不影响其他任务', () async {
    DateTime now = base;
    final Harness harness = Harness(clock: () => now);
    harness.service.addDynamicTask(
        <String, Object?>{'id': 'good', 'prompt': 'ping', 'every': 600});
    harness.service.addDynamicTask(
        <String, Object?>{'id': 'bad', 'prompt': 'pong', 'cron': '0 9 * * *'});
    final CronTask broken = harness.service.findTask('bad')!;
    broken.cronParsed = null;
    broken.cronNext = null;
    final CronRuntime runtime = CronRuntime(
      service: harness.service,
      deliver: harness.accept,
      options: CronRuntimeOptions(
        clock: () => now,
        tickSeconds: 3600,
        firstTickDelay: const Duration(hours: 1),
      ),
    );
    addTearDown(runtime.dispose);

    now = base.add(const Duration(seconds: 601));
    await runtime.tick();
    expect(harness.delivered, hasLength(1), reason: 'good 正常触发');
    expect(harness.warnings.join('\n'), contains('bad'),
        reason: 'bad 的故障被隔离并告警');
  });
}
