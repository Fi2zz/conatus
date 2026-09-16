import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_cron/conatus_cron.dart';
import 'package:test/test.dart';

final DateTime base = DateTime(2026, 9, 16, 10);

class Harness {
  Harness({DateTime Function()? clock, bool Function(String framing)? deliver})
      : warnings = <String>[],
        delivered = <String>[],
        records = <String>[],
        _deliver = deliver {
    final Directory dir =
        Directory.systemTemp.createTempSync('conatus-cron-runtime-');
    addTearDown(() => dir.deleteSync(recursive: true));
    storage = CronStorage(
      tasksPath: '${dir.path}/cron-tasks.json',
      historyPath: '${dir.path}/cron-history.jsonl',
    );
    service = CronService(
      storage: storage,
      clock: clock ?? () => base,
      onWarning: warnings.add,
    );
  }

  late final CronStorage storage;
  late final CronService service;
  final List<String> warnings;
  final List<String> delivered;
  final List<String> records;
  final bool Function(String framing)? _deliver;

  Future<bool> accept(String recordId, String framing) async {
    delivered.add(framing);
    records.add(recordId);
    final bool Function(String framing)? custom = _deliver;
    return custom == null ? true : custom(framing);
  }
}

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
    expect(harness.delivered.single, contains('[cron] Scheduled task "demo" fired.'));
    expect(harness.delivered.single, contains('<task>\nping\n</task>'));

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
    expect(harness.service.listHistory(), isEmpty,
        reason: '第二次仍被拒，槽位保持未消费');
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
      deliver: (String recordId, String framing) async =>
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
      deliver: (String recordId, String framing) async => false,
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
      throwsA(isA<CronException>().having(
          (CronException e) => e.code, 'code', CronErrorCode.deliveryUnavailable)),
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
        notifier: (String title, String body) =>
            notifications.add('$title|$body'),
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
    expect(notifications, <String>['定时任务完成：demo|构建通过']);
    expect(harness.service.listHistory().single.status, CronRunStatus.completed);

    await runtime.tick();
    now = base.add(const Duration(seconds: 1202));
    await runtime.tick();
    runtime.finishRun(harness.records.last, ok: false);
    expect(notifications.last, '定时任务失败：demo|原始 prompt',
        reason: '无摘要时回退到 prompt 快照');
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

  test('dispose 停表：首 tick 前释放不再触发', () async {
    final Harness harness = Harness(clock: DateTime.now);
    harness.service.addDynamicTask(<String, Object?>{
      'id': 'due',
      'prompt': 'ping',
      'at': DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toIso8601String(),
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
      'at': DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toIso8601String(),
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
