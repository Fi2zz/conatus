/// 把已解码的变更应用到折叠结果，并从会话事件流折叠出活动提醒。
///
/// 折叠只接受合法转换：id 复用、指向非活动记录的删除或派发都会抛
/// [ScheduleLogException]。活动记录保持创建顺序，[ScheduleFold.seenIds] 保留所有
/// 用过的标识，因此标识永不复用。
library;

import 'schedule_changes.dart';
import 'schedule_errors.dart';
import 'schedule_recurrence.dart';
import 'schedule_types.dart';
import 'session_types.dart';

/// 折叠一段按序事件流，得到活动记录与用过的标识。
///
/// 传入的应当是会话自身拥有的事件（`Session.ownEvents`），这样 fork 出的会话不会
/// 继承父会话的活动提醒。
ScheduleFold foldScheduleEvents(Iterable<SessionEvent> events) {
  final List<ScheduleChange> changes = <ScheduleChange>[];
  for (final SessionEvent event in events) {
    if (event.type == kScheduleChangeEvent) {
      changes.add(decodeScheduleChange(event.data));
    }
  }
  return applyScheduleChanges(
    ScheduleFold(
      active: const <ScheduleRecord>[],
      seenIds: const <String>[],
    ),
    changes,
  );
}

/// 按序应用一批已解码变更，返回新的折叠结果。
ScheduleFold applyScheduleChanges(
  ScheduleFold folded,
  Iterable<ScheduleChange> changes,
) {
  final Map<String, ScheduleRecord> active = <String, ScheduleRecord>{
    for (final ScheduleRecord record in folded.active) record.id: record,
  };
  final Set<String> seen = <String>{...folded.seenIds};
  for (final ScheduleChange change in changes) {
    switch (change) {
      case ScheduleCreateChange(record: final ScheduleRecord record):
        if (seen.contains(record.id)) {
          throw ScheduleLogException(
              'schedule id ${quoteScheduleId(record.id)} was reused');
        }
        seen.add(record.id);
        active[record.id] = record;
      case ScheduleDeleteChange(id: final String id):
        if (active.remove(id) == null) {
          throw ScheduleLogException(
              'schedule delete targets inactive id ${quoteScheduleId(id)}');
        }
      case ScheduleDispatchChange(
          id: final String id,
          acceptedAt: final DateTime? acceptedAt
        ):
        final ScheduleRecord? record = active[id];
        if (record == null) {
          throw ScheduleLogException(
              'schedule dispatch targets inactive id ${quoteScheduleId(id)}');
        }
        final ScheduleRecord? next = _dispatched(record, acceptedAt);
        if (next == null) {
          active.remove(id);
        } else {
          active[id] = next;
        }
    }
  }
  return ScheduleFold(
    active: active.values.toList(),
    seenIds: seen.toList(),
  );
}

/// 分配下一个可读标识，永不复用任何用过的标识。
String allocateScheduleId(ScheduleFold folded) {
  final Set<String> seen = folded.seenIds.toSet();
  int sequence = seen.length + 1;
  String candidate = 'schedule-$sequence';
  while (seen.contains(candidate)) {
    sequence += 1;
    candidate = 'schedule-$sequence';
  }
  return candidate;
}

ScheduleRecord? _dispatched(ScheduleRecord record, DateTime? acceptedAt) {
  if (record.kind != ScheduleKind.every) {
    if (acceptedAt != null) {
      throw const ScheduleLogException(
          'one-shot dispatch must not contain acceptedAt');
    }
    return null;
  }
  if (acceptedAt == null) {
    throw const ScheduleLogException('every dispatch must contain acceptedAt');
  }
  final DateTime? next =
      resolveEveryOccurrence(record, acceptedAt).nextScheduledAt;
  return next == null ? null : record.withScheduledAt(next);
}
