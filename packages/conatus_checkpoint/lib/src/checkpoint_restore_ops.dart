/// 轮次恢复的编排：选目标轮次、恢复、回传对话切点。
///
/// 从 [CheckpointManager] 拆出，管理器只留绑定 / 链 / 策略。`rewind` 的
/// 「往回 N 轮并钳制」与 `restoreTo` 的「显式会话 + 轮次」共用这里的恢复主体。
library;

import 'checkpoint_store.dart';
import 'checkpoint_types.dart';

/// 恢复到 [sessionId] 的 [turn] 轮；该轮不存在返回 `null`。
Future<CheckpointRewindResult?> restoreCheckpoint(
  CheckpointStore store,
  String sessionId,
  int turn,
) async {
  if (!store.turnsOf(sessionId).contains(turn)) return null;
  final CheckpointManifest manifest = await store.loadManifest(sessionId, turn);
  final CheckpointRestore restore = await store.restore(sessionId, turn);
  return CheckpointRewindResult(
    turn: turn,
    restore: restore,
    lastEventId: manifest.lastEventId,
  );
}

/// 往回 [steps] 轮（`< 1` 按 1），钳制到最早检查点；无检查点返回 `null`。
Future<CheckpointRewindResult?> rewindCheckpoint(
  CheckpointStore store,
  String sessionId,
  int steps,
) async {
  final List<CheckpointInfo> infos = store.list(sessionId);
  if (infos.isEmpty) return null;
  final List<int> turns = <int>[
    for (final CheckpointInfo info in infos) info.turn,
  ];
  final int back = steps < 1 ? 1 : steps;
  final int target =
      turns.length > back ? turns[turns.length - back - 1] : turns.first;
  return restoreCheckpoint(store, sessionId, target);
}
