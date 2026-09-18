import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_cron/conatus_cron.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('runTaskNow 立即触发；未知 id 与投递不可用抛 CronException', () async {
    final Harness harness = Harness();
    harness.service.addDynamicTask(<String, Object?>{
      'id': 'demo',
      'prompt': 'ping',
      'at': '2026-09-20T09:00:00+08:00',
    });
    final CronRuntime runtime = CronRuntime(
      service: harness.service,
      deliver: harness.accept,
      options: const CronRuntimeOptions(
        tickSeconds: 3600,
        firstTickDelay: Duration(hours: 1),
      ),
    );
    addTearDown(runtime.dispose);

    final CronRunRecord record = await runtime.runTaskNow('demo');
    expect(record.taskId, 'demo');
    expect(harness.delivered, hasLength(1));
    expect(harness.service.listHistory(), hasLength(1));
    expect(harness.service.findTask('demo')!.firedAt, isNotNull,
        reason: 'runTaskNow 也消费 at 槽位');

    expect(
      () => runtime.runTaskNow('missing'),
      throwsA(isA<CronException>()
          .having((CronException e) => e.code, 'code', CronErrorCode.notFound)),
    );

    final CronRuntime refusing = CronRuntime(
      service: harness.service,
      deliver: (String recordId, String framing, CronTask task) async => false,
      options: const CronRuntimeOptions(
        tickSeconds: 3600,
        firstTickDelay: Duration(hours: 1),
      ),
    );
    addTearDown(refusing.dispose);
    harness.service.addDynamicTask(
        <String, Object?>{'id': 'later', 'prompt': 'ping', 'every': 600});
    expect(
      () => refusing.runTaskNow('later'),
      throwsA(isA<CronException>().having((CronException e) => e.code, 'code',
          CronErrorCode.deliveryUnavailable)),
    );
  });

  test('notifier 在 finishRun 时收到完成/失败通知', () async {
    DateTime now = base;
    final Harness harness = Harness(clock: () => now);
    harness.service.addDynamicTask(
        <String, Object?>{'id': 'demo', 'prompt': '原始 prompt', 'every': 600});
    final List<String> notifications = <String>[];
    final CronRuntime runtime = CronRuntime(
      service: harness.service,
      deliver: harness.accept,
      options: CronRuntimeOptions(
        clock: () => now,
        notifier: (String title, String body, CronTask task) =>
            notifications.add('$title|$body|${task.id}'),
        tickSeconds: 3600,
        firstTickDelay: const Duration(hours: 1),
      ),
    );
    addTearDown(runtime.dispose);

    now = base.add(const Duration(seconds: 601));
    await runtime.tick();
    expect(harness.records, hasLength(1));
    final String recordId = harness.records.single;

    runtime.finishRun(recordId, ok: true, excerpt: '构建通过');
    expect(notifications, <String>['定时任务完成：原始 prompt|构建通过|demo']);
    expect(
        harness.service.listHistory().single.status, CronRunStatus.completed);

    await runtime.tick();
    now = base.add(const Duration(seconds: 1202));
    await runtime.tick();
    runtime.finishRun(harness.records.last, ok: false);
    expect(notifications.last, '定时任务失败：原始 prompt|原始 prompt|demo',
        reason: '无摘要时回退到 prompt 快照');
  });

  test('dispose 停表：首 tick 前释放不再触发', () async {
    final Harness harness = Harness(clock: DateTime.now);
    harness.service.addDynamicTask(<String, Object?>{
      'id': 'due',
      'prompt': 'ping',
      'at':
          DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String(),
    });
    final CronRuntime runtime = CronRuntime(
      service: harness.service,
      deliver: harness.accept,
      options: const CronRuntimeOptions(
        tickSeconds: 3600,
        firstTickDelay: Duration(milliseconds: 30),
      ),
    );
    runtime.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(harness.delivered, isEmpty);
  });

  test('首 tick 按延迟触发（真实定时器）', () async {
    final Harness harness = Harness(clock: DateTime.now);
    harness.service.addDynamicTask(<String, Object?>{
      'id': 'due',
      'prompt': 'ping',
      'at':
          DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String(),
    });
    final CronRuntime runtime = CronRuntime(
      service: harness.service,
      deliver: harness.accept,
      options: const CronRuntimeOptions(
        tickSeconds: 3600,
        firstTickDelay: Duration(milliseconds: 30),
      ),
    );
    addTearDown(runtime.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(harness.delivered, hasLength(1));
  });

  test('提供进上下文并随释放停表', () async {
    final Harness harness = Harness();
    final Context ctx = Context.root();
    final CronService service = provideCron(ctx, storage: harness.storage);
    final CronRuntime runtime = provideCronRuntime(
      ctx,
      deliver: harness.accept,
      options: const CronRuntimeOptions(
        tickSeconds: 3600,
        firstTickDelay: Duration(hours: 1),
      ),
    );
    expect(ctx.cron, same(service));
    expect(ctx.cronRuntime, same(runtime));
    expect(runtime.service, same(service));
    ctx.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
}
