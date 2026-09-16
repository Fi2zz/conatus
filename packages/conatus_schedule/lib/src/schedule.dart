/// schedule 服务：把提醒写进会话事件流，并从中折叠出活动提醒。
///
/// 提醒没有独立存储：唯一权威是会话里的 `schedule/change` 事件，因此会话落盘后
/// 重启即可自动重建全部活动提醒。读取与决策前会先等待一次持久化检查点；创建与
/// 删除在追加之后还会等待第二次检查点，无法确认时抛
/// [SchedulePersistenceException]，而不是声称成功。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'schedule_errors.dart';
import 'schedule_fold.dart';
import 'schedule_rules.dart';
import 'schedule_time.dart';
import 'schedule_types.dart';

/// 会话本地的提醒服务。
class SessionSchedule {
  /// 构造一个服务实例。
  SessionSchedule({
    required this.session,
    this.sessions,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// 被管理的会话。
  final Session session;

  /// 可选的会话存储；提供时才会执行持久化检查点。
  final SessionStore? sessions;

  final DateTime Function() _clock;

  /// 采样当前墙钟。
  DateTime now() => _clock();

  /// 折叠出当前的活动提醒与用过的标识。
  ScheduleFold fold() => foldScheduleEvents(session.ownEvents);

  /// 等待一次持久化检查点；没有存储后端时立即返回。
  Future<void> checkpoint(String operation, [String? id]) async {
    final SessionStore? store = sessions;
    if (store == null) return;
    try {
      await store.flush();
    } on Object {
      throw SchedulePersistenceException(operation, id);
    }
  }

  /// 按创建顺序列出全部活动提醒。
  Future<List<ScheduleView>> list() async {
    await checkpoint(ScheduleOperation.list);
    final DateTime at = now();
    return <ScheduleView>[
      for (final ScheduleRecord record in fold().active)
        scheduleView(record, at),
    ];
  }

  /// 创建一条提醒；三个选择器互斥，由调用方保证只给一个。
  Future<ScheduleView> create({
    required String prompt,
    Object? afterSeconds,
    Object? at,
    Object? everySeconds,
  }) async {
    await checkpoint(ScheduleOperation.create);
    final ScheduleFold folded = fold();
    final String id = allocateScheduleId(folded);
    final DateTime createdAt = now();
    final ScheduleRecord record;
    if (at != null) {
      record = createAtRecord(id: id, prompt: prompt, at: at, now: createdAt);
    } else if (afterSeconds != null) {
      record = createAfterRecord(
          id: id, prompt: prompt, afterSeconds: afterSeconds, now: createdAt);
    } else {
      record = createEveryRecord(
          id: id, prompt: prompt, everySeconds: everySeconds, now: createdAt);
    }
    session.append(kScheduleChangeEvent, data: _createPayload(record));
    await checkpoint(ScheduleOperation.create, id);
    return scheduleView(record, now());
  }

  /// 删除一条活动提醒；目标不存在时返回 `deleted: false` 且不改动任何状态。
  Future<ScheduleDeleteResult> delete(String id) async {
    await checkpoint(ScheduleOperation.delete, id);
    if (fold().find(id) == null) {
      return ScheduleDeleteResult(id: id, deleted: false);
    }
    session.append(kScheduleChangeEvent, data: <String, Object?>{
      'version': kScheduleChangeVersion,
      'operation': 'delete',
      'id': id,
    });
    await checkpoint(ScheduleOperation.delete, id);
    return ScheduleDeleteResult(id: id, deleted: true);
  }

  /// 把一次派发写入历史；固定间隔派发必须带 [acceptedAt]。
  void recordDispatch(String id, {DateTime? acceptedAt}) {
    session.append(kScheduleChangeEvent, data: <String, Object?>{
      'version': kScheduleChangeVersion,
      'operation': 'dispatch',
      'id': id,
      if (acceptedAt != null) 'acceptedAt': formatUtcInstant(acceptedAt),
    });
  }

  Map<String, Object?> _createPayload(ScheduleRecord record) =>
      <String, Object?>{
        'version': kScheduleChangeVersion,
        'operation': 'create',
        'schedule': record.toJson(),
      };
}

/// 把 [SessionSchedule] 作为 `'schedule'` 服务提供到上下文。
///
/// 未显式传入 [sessions] 时复用上下文里已提供的 `'sessions'`；没有会话存储时不会
/// 执行持久化检查点。
SessionSchedule provideSessionSchedule(
  Context ctx, {
  required Session session,
  SessionStore? sessions,
  DateTime Function()? clock,
}) {
  final SessionSchedule schedule = SessionSchedule(
    session: session,
    sessions: sessions ?? ctx.get<SessionStore>('sessions'),
    clock: clock,
  );
  ctx.provide('schedule', schedule);
  return schedule;
}

/// `ctx.schedule`：当前上下文可见的提醒服务。
extension ScheduleContext on Context {
  /// 当前上下文提供的提醒服务。
  SessionSchedule get schedule => require<SessionSchedule>('schedule');
}
