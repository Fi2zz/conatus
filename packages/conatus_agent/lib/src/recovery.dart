/// recovery：会话快照的保存与恢复。
///
/// [RecoveryService.snapshot] 把一条会话的全部事件存为快照（重建后可用
/// [RecoveryService.restore] 还原 Session 继续对话）；`provideRecovery` 在上下文里
/// 已有 `'database'` 时默认用 [DatabaseSnapshotStore]，否则退回内存实现。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'snapshot.dart';

/// 恢复服务：快照 + 还原。
class RecoveryService {
  RecoveryService({required this.store});

  /// 快照存储。
  final SnapshotStore store;

  /// 保存一条会话的快照。建议每轮结束或会话释放时调用。
  Future<void> snapshot(Session session) => store.save(SessionSnapshot(
        sessionId: session.id,
        events: session.events,
        savedAt: DateTime.now(),
      ));

  /// 载入快照；不存在或版本不符抛 [RecoveryException]。
  Future<SessionSnapshot> load(String sessionId) async {
    final SessionSnapshot? snapshot = await store.load(sessionId);
    if (snapshot == null) {
      throw RecoveryException('not-found', '没有会话 "$sessionId" 的快照');
    }
    return snapshot;
  }

  /// 由快照还原一条会话（带事件种子），可直接交给 Agent Loop 继续对话。
  Future<Session> restore(String sessionId) async {
    final SessionSnapshot snapshot = await load(sessionId);
    return Session(id: snapshot.sessionId, seed: snapshot.events);
  }

  /// 已保存快照的会话 id。
  Future<List<String>> list() => store.list();

  /// 删除快照。
  Future<void> delete(String sessionId) => store.delete(sessionId);
}

/// `ctx.recovery`：当前上下文可见的恢复服务。
extension RecoveryContext on Context {
  /// 取当前上下文可见的 [RecoveryService]（未提供时抛 [StateError]）。
  RecoveryService get recovery => require<RecoveryService>('recovery');
}

/// 提供 `'recovery'` 服务并返回它。
///
/// 存储优先级：[store] > `'database'` 服务（[DatabaseSnapshotStore]）> 内存实现。
RecoveryService provideRecovery(
  Context ctx, {
  RecoveryService? recovery,
  SnapshotStore? store,
  Database? database,
}) {
  final Database? hub = database ?? ctx.get<Database>('database');
  final SnapshotStore resolvedStore = store ??
      (hub == null ? MemorySnapshotStore() : DatabaseSnapshotStore(hub));
  final RecoveryService service =
      recovery ?? RecoveryService(store: resolvedStore);
  ctx.provide('recovery', service);
  return service;
}
