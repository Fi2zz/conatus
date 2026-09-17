import 'dart:io';

import 'package:conatus_cron/conatus_cron.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('持久化 round-trip', () {
    test('新实例读旧文件：运行戳与覆盖恢复，已消费槽位不重发', () {
      final built = buildService();
      built.service.addDynamicTask(
          <String, Object?>{'id': 'loop', 'prompt': 'a', 'every': 600});
      built.service.addDynamicTask(<String, Object?>{
        'id': 'once',
        'prompt': 'b',
        'at': '2026-09-15T16:00:00+08:00',
      });
      fireOnce(built.service, 'loop', base);
      fireOnce(built.service, 'once', base);
      built.service.setEnabled('loop', false);

      final CronService restored = CronService(
        storage: built.storage,
        clock: () => base,
      );
      final CronTask loop = restored.findTask('loop')!;
      expect(
          loop.lastRunAt!.millisecondsSinceEpoch, base.millisecondsSinceEpoch);
      expect(loop.enabledOverride, isFalse);
      final CronTask once = restored.findTask('once')!;
      expect(once.firedAt!.millisecondsSinceEpoch, base.millisecondsSinceEpoch);

      expect(
          dueSlot(
              loop, base.add(const Duration(seconds: 600)), restored.startedAt),
          isNull,
          reason: '停用任务不触发');
      loop.enabledOverride = null;
      expect(
          dueSlot(
              loop, base.add(const Duration(seconds: 599)), restored.startedAt),
          isNull,
          reason: 'lastRunAt 已消费该时段');
      expect(
          dueSlot(
              loop, base.add(const Duration(seconds: 600)), restored.startedAt),
          isNotNull);
      expect(
          dueSlot(once, base.add(const Duration(days: 1)), restored.startedAt),
          isNull,
          reason: 'at 任务消费后不再触发');
    });

    test('历史封顶 500，seq 连续，最新在前', () {
      final built = buildService();
      built.service.addDynamicTask(
          <String, Object?>{'id': 't', 'prompt': 'a', 'every': 600});
      for (int i = 0; i < 600; i++) {
        fireOnce(built.service, 't', base.add(Duration(seconds: i)));
      }
      final List<CronRunRecord> records =
          built.service.listHistory(limit: 1000);
      expect(records, hasLength(kCronMaxHistory));
      expect(records.first.seq, 599);
      expect(records.last.seq, 100);
      final File historyFile = File('${built.dir.path}/cron-history.jsonl');
      expect(historyFile.readAsStringSync().trim().split('\n'),
          hasLength(kCronMaxHistory));
    });

    test('finishRun 推进终态、截断摘要并持久化', () {
      final built = buildService();
      built.service.addDynamicTask(
          <String, Object?>{'id': 't', 'prompt': 'a', 'every': 600});
      final CronRunRecord record = fireOnce(built.service, 't', base);
      expect(record.status, CronRunStatus.delivered);

      final String longExcerpt = '结' * 400;
      final CronRunRecord? finished =
          built.service.finishRun(record.id, ok: false, excerpt: longExcerpt);
      expect(finished!.status, CronRunStatus.failed);
      expect(finished.completedAt, base);
      expect(finished.excerpt, hasLength(kCronExcerptLength));

      final CronService restored =
          CronService(storage: built.storage, clock: () => base);
      final List<CronRunRecord> records = restored.listHistory();
      expect(records.single.status, CronRunStatus.failed);
      expect(records.single.excerpt, hasLength(kCronExcerptLength));
      expect(restored.finishRun('run-missing', ok: true), isNull);
    });
  });
}
