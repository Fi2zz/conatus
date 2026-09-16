import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

ScheduleRecord everyRecord({
  String id = 'schedule-1',
  int everySeconds = 300,
  DateTime? scheduledAt,
}) =>
    ScheduleRecord(
      id: id,
      kind: ScheduleKind.every,
      prompt: '检查构建',
      everySeconds: everySeconds,
      scheduledAt: scheduledAt ?? DateTime.utc(2026, 8, 6),
    );

void main() {
  group('固定间隔发生算术', () {
    test('只取最新一个锚点对齐的到期时点', () {
      final EveryOccurrence result = resolveEveryOccurrence(
          everyRecord(), DateTime.utc(2026, 8, 6, 0, 12, 30));
      expect(result.occurrenceAt, DateTime.utc(2026, 8, 6, 0, 10));
      expect(result.nextScheduledAt, DateTime.utc(2026, 8, 6, 0, 15));
    });

    test('决策时点恰好等于目标时不跳过任何间隔', () {
      final EveryOccurrence result =
          resolveEveryOccurrence(everyRecord(), DateTime.utc(2026, 8, 6));
      expect(result.occurrenceAt, DateTime.utc(2026, 8, 6));
      expect(result.nextScheduledAt, DateTime.utc(2026, 8, 6, 0, 5));
    });

    test('错过大量间隔也不枚举积压', () {
      final EveryOccurrence result = resolveEveryOccurrence(
        everyRecord(everySeconds: 86400),
        DateTime.utc(2029, 8, 6, 12),
      );
      expect(result.occurrenceAt, DateTime.utc(2029, 8, 6));
      expect(result.nextScheduledAt, DateTime.utc(2029, 8, 7));
    });

    test('下一个目标越出范围时记录耗尽', () {
      final EveryOccurrence result = resolveEveryOccurrence(
        everyRecord(scheduledAt: DateTime.utc(9999, 12, 31, 23, 59, 59)),
        DateTime.utc(9999, 12, 31, 23, 59, 59, 999),
      );
      expect(result.occurrenceAt, DateTime.utc(9999, 12, 31, 23, 59, 59));
      expect(result.nextScheduledAt, isNull);
    });

    test('早于活动目标的决策时点被拒绝', () {
      expect(
        () => resolveEveryOccurrence(
            everyRecord(), DateTime.utc(2026, 8, 5, 23, 59)),
        throwsA(isA<ScheduleLogException>()),
      );
      expect(
        () => resolveEveryOccurrence(everyRecord(), DateTime.utc(10000)),
        throwsA(isA<ScheduleLogException>()),
      );
    });
  });

  group('到期决策', () {
    test('一次性提醒优先于固定间隔批次', () {
      final ScheduleFold folded = ScheduleFold(
        active: <ScheduleRecord>[
          ScheduleRecord(
            id: 'schedule-1',
            kind: ScheduleKind.every,
            prompt: '循环',
            everySeconds: 300,
            scheduledAt: DateTime.utc(2026, 8, 6),
          ),
          ScheduleRecord(
            id: 'schedule-2',
            kind: ScheduleKind.at,
            prompt: '一次',
            scheduledAt: DateTime.utc(2026, 8, 6, 0, 1),
          ),
        ],
        seenIds: const <String>['schedule-1', 'schedule-2'],
      );
      final DueDecision decision =
          dueDecision(folded, DateTime.utc(2026, 8, 6, 0, 2));
      expect(decision, isA<ScheduleOneShotDue>());
      expect((decision as ScheduleOneShotDue).record.id, 'schedule-2');
    });

    test('同目标的一次性提醒按创建顺序取最先创建的', () {
      final ScheduleFold folded = ScheduleFold(
        active: <ScheduleRecord>[
          ScheduleRecord(
              id: 'b',
              kind: ScheduleKind.at,
              prompt: 'b',
              scheduledAt: DateTime.utc(2026, 8, 6)),
          ScheduleRecord(
              id: 'a',
              kind: ScheduleKind.at,
              prompt: 'a',
              scheduledAt: DateTime.utc(2026, 8, 6)),
        ],
        seenIds: const <String>['b', 'a'],
      );
      expect(
          (dueDecision(folded, DateTime.utc(2026, 8, 6)) as ScheduleOneShotDue)
              .record
              .id,
          'b');
    });

    test('批次内每条只取最新发生时点并共用决策时点', () {
      final DateTime now = DateTime.utc(2026, 8, 6, 0, 12);
      final ScheduleFold folded = ScheduleFold(
        active: <ScheduleRecord>[everyRecord()],
        seenIds: const <String>['schedule-1'],
      );
      final DueDecision decision = dueDecision(folded, now);
      final ScheduleEveryBatchDue batch = decision as ScheduleEveryBatchDue;
      expect(batch.acceptedAt, now);
      expect(
          batch.reminders.single.occurrenceAt, DateTime.utc(2026, 8, 6, 0, 10));
    });

    test('没有到期记录时给出下一次唤醒时刻', () {
      final ScheduleFold folded = ScheduleFold(
        active: <ScheduleRecord>[
          ScheduleRecord(
              id: 'a',
              kind: ScheduleKind.at,
              prompt: 'a',
              scheduledAt: DateTime.utc(2026, 8, 6, 1)),
        ],
        seenIds: const <String>['a'],
      );
      final ScheduleWait wait =
          dueDecision(folded, DateTime.utc(2026, 8, 6)) as ScheduleWait;
      expect(wait.target, DateTime.utc(2026, 8, 6, 1));
      expect(
        (dueDecision(
                ScheduleFold(
                    active: const <ScheduleRecord>[],
                    seenIds: const <String>[]),
                DateTime.utc(2026, 8, 6)) as ScheduleWait)
            .target,
        isNull,
      );
    });
  });
}
