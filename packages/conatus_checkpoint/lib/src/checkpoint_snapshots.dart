/// 快照动作：绑定/重建基线、每轮差量，以及把存储异常转成提示文案。
///
/// 这些动作都在 [CheckpointTimeline] 的串行链上执行（调用方负责排队），
/// 这里只管「写什么、失败怎么报」。从 [CheckpointManager] 拆出后，管理器
/// 只保留对外 API 与策略，类回到行数约束内。
library;

import 'checkpoint_store.dart';
import 'checkpoint_timeline.dart';

/// [CheckpointManager.bind] 的链上主体：有历史就接管，否则写 turn 0 基线。
Future<String?> bindSnapshot(
  CheckpointTimeline timeline,
  CheckpointStore store,
  String sessionId, {
  String? lastEventId,
}) async {
  final List<int> turns;
  try {
    turns = store.turnsOf(sessionId);
  } catch (error) {
    return '检查点读取失败：$error';
  }
  if (turns.isEmpty) {
    return writeBaseSnapshot(store, sessionId, lastEventId: lastEventId);
  }
  timeline.setTurn(turns.last);
  return null;
}

/// 同步读最大轮次（给 UI 即时值）；读失败按 0，错误由 [bindSnapshot] 报告。
int latestTurnOrZero(CheckpointStore store, String sessionId) {
  try {
    final List<int> turns = store.turnsOf(sessionId);
    return turns.isEmpty ? 0 : turns.last;
  } catch (_) {
    return 0;
  }
}

/// 写 turn 0 全量基线（清旧时间线后落盘）。失败返回错误说明。
Future<String?> writeBaseSnapshot(
  CheckpointStore store,
  String sessionId, {
  String? lastEventId,
}) async {
  try {
    if (store.list(sessionId).isNotEmpty) {
      await store.clearSession(sessionId);
    }
    await store.snapshot(sessionId, 0, lastEventId: lastEventId);
    return null;
  } catch (error) {
    return '检查点初始快照失败：$error';
  }
}

/// 每轮收口后写差量：轮次 +1 并快照。失败返回错误说明（不抛出）。
Future<String?> recordSnapshot(
  CheckpointTimeline timeline,
  CheckpointStore store,
  bool enabled, {
  String? lastEventId,
}) async {
  final String? id = timeline.sessionId;
  if (id == null) return null;
  final int turn = timeline.nextTurn();
  if (!enabled) return null;
  try {
    await store.snapshot(id, turn, lastEventId: lastEventId);
    return null;
  } catch (error) {
    return '检查点保存失败：$error';
  }
}
