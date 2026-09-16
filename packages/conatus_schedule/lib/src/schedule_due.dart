/// 到期决策：选出下一条要交付的一次性提醒、一批固定间隔提醒，或下一次唤醒时刻。
///
/// 决策是纯函数：输入折叠结果与单次墙钟采样，输出确定结果。一次性提醒优先于
/// 固定间隔批次，且一次只交付一条；批次内每条记录只贡献最新一个发生时点。
library;

import 'schedule_recurrence.dart';
import 'schedule_types.dart';

/// 一次到期决策的结果。
sealed class DueDecision {
  /// 构造一个决策结果。
  const DueDecision();
}

/// 当前没有到期记录，可选择安排一次唤醒。
class ScheduleWait extends DueDecision {
  /// 构造一次等待决策。
  const ScheduleWait(this.target);

  /// 严格晚于决策时刻的最小目标；没有未来记录时为 `null`（保持静默）。
  final DateTime? target;
}

/// 交付一条到期的一次性提醒。
class ScheduleOneShotDue extends DueDecision {
  /// 构造一次性交付决策。
  const ScheduleOneShotDue(this.record);

  /// 被选中的记录。
  final ScheduleRecord record;
}

/// 交付一批到期的固定间隔提醒，整批共用同一个决策时点。
class ScheduleEveryBatchDue extends DueDecision {
  /// 构造批次交付决策。
  const ScheduleEveryBatchDue({
    required this.reminders,
    required this.acceptedAt,
  });

  /// 按目标时间与创建顺序排列的到期项。
  final List<ScheduleDue> reminders;

  /// 写入每条 dispatch 事件的决策时点。
  final DateTime acceptedAt;
}

/// 选定一次到期决策。
DueDecision dueDecision(ScheduleFold folded, DateTime now) {
  final List<ScheduleRecord> oneShot = _targetsAt(folded.active, now, false);
  if (oneShot.isNotEmpty) return ScheduleOneShotDue(oneShot.first);

  final List<ScheduleRecord> recurring = _targetsAt(folded.active, now, true);
  if (recurring.isNotEmpty) {
    return ScheduleEveryBatchDue(
      reminders: <ScheduleDue>[
        for (final ScheduleRecord record in recurring)
          ScheduleDue(
            record: record,
            occurrenceAt: resolveEveryOccurrence(record, now).occurrenceAt,
          ),
      ],
      acceptedAt: now,
    );
  }
  return ScheduleWait(_nextTarget(folded.active, now));
}

List<ScheduleRecord> _targetsAt(
  List<ScheduleRecord> active,
  DateTime now,
  bool recurring,
) {
  final List<(ScheduleRecord, int)> indexed = <(ScheduleRecord, int)>[];
  for (int index = 0; index < active.length; index++) {
    final ScheduleRecord record = active[index];
    final bool every = record.kind == ScheduleKind.every;
    if (every == recurring && !record.scheduledAt.isAfter(now)) {
      indexed.add((record, index));
    }
  }
  indexed.sort(((ScheduleRecord, int) left, (ScheduleRecord, int) right) {
    final int byTarget = left.$1.scheduledAt.compareTo(right.$1.scheduledAt);
    return byTarget != 0 ? byTarget : left.$2.compareTo(right.$2);
  });
  return <ScheduleRecord>[
    for (final (ScheduleRecord, int) entry in indexed) entry.$1
  ];
}

DateTime? _nextTarget(List<ScheduleRecord> active, DateTime now) {
  DateTime? target;
  for (final ScheduleRecord record in active) {
    if (!record.scheduledAt.isAfter(now)) continue;
    if (target == null || record.scheduledAt.isBefore(target)) {
      target = record.scheduledAt;
    }
  }
  return target;
}
