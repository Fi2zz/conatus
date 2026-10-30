/// 归档检查点的两轮差异：集合差 + 交集内容比对。
///
/// 归档差量是相对 base 记录的（不是相对上一轮），所以「同一文件在两轮里都
/// 偏离 base」不等于它在两轮之间变过——交集必须逐字节确认。与
/// `checkpoint_lookup.dart` 合起来是 `/diff turn` 的数据源。
library;

import 'checkpoint_changes.dart';
import 'checkpoint_lookup.dart';
import 'checkpoint_paths.dart';
import 'checkpoint_store_archive.dart';
import 'checkpoint_types.dart';

/// [fromTurn] → [toTurn] 的文件级变化（路径排序）。
///
/// 先按两轮的文件集分类新增 / 删除，再对「任一端的差量清单点名」的交集路径
/// 做内容比对——差量清单只记相对 base 的变化，同一文件在两轮里都偏离 base
/// 时未必真的变过。
Future<List<CheckpointFileChange>> archiveChangesBetween(
  ArchiveCheckpointStore store,
  String sessionId,
  int fromTurn,
  int toTurn,
) async {
  _requireTurn(store, sessionId, fromTurn);
  _requireTurn(store, sessionId, toTurn);
  if (fromTurn == toTurn) return const <CheckpointFileChange>[];
  final _TurnPair pair = _TurnPair(store, sessionId, fromTurn, toTurn);
  final List<CheckpointFileChange> changes = await pair.diff();
  changes.sort((CheckpointFileChange a, CheckpointFileChange b) {
    return a.path.compareTo(b.path);
  });
  return changes;
}

/// 轮次不存在 / 归档缺失抛 `missing-checkpoint`（与影子实现同码）。
void _requireTurn(ArchiveCheckpointStore store, String sessionId, int turn) {
  if (!store.turnsOf(sessionId).contains(turn)) {
    throw CheckpointException(
      'missing-checkpoint',
      '检查点 $turn 不存在（会话 $sessionId）',
    );
  }
  requireArchiveFile(store, sessionId, turn);
}

/// 两轮比较的上下文（避免把 store / 会话 / 两端轮次一路透传）。
class _TurnPair {
  const _TurnPair(this.store, this.sessionId, this.fromTurn, this.toTurn);

  final ArchiveCheckpointStore store;
  final String sessionId;
  final int fromTurn;
  final int toTurn;

  /// 两轮的差异：集合差 + 交集里的内容比对。
  Future<List<CheckpointFileChange>> diff() async {
    final _TurnState before = await _stateAt(fromTurn);
    final _TurnState after = await _stateAt(toTurn);
    return <CheckpointFileChange>[
      for (final String path in after.paths.difference(before.paths))
        if (_visible(path)) CheckpointFileChange(path: path, status: 'added'),
      for (final String path in before.paths.difference(after.paths))
        if (_visible(path)) CheckpointFileChange(path: path, status: 'deleted'),
      ...await _modified(before, after),
    ];
  }

  /// 某轮的文件集 + 该轮差量点名过的路径（turn 0 没有差量）。
  Future<_TurnState> _stateAt(int turn) async {
    final CheckpointManifest base = await store.loadManifest(sessionId, 0);
    final Set<String> basePaths = <String>{
      for (final CheckpointFileEntry entry in base.files) entry.path,
    };
    if (turn == 0) {
      return _TurnState(paths: basePaths, changed: const <String>{});
    }
    final CheckpointManifest delta = await store.loadManifest(sessionId, turn);
    return _TurnState(
      paths: <String>{
        ...basePaths.difference(delta.deleted.toSet()),
        ...delta.changed,
      },
      changed: delta.changed.toSet(),
    );
  }

  /// 交集里「可能改过」的路径逐字节确认（两端都读过才比）。
  Future<List<CheckpointFileChange>> _modified(
    _TurnState before,
    _TurnState after,
  ) async {
    final Set<String> suspects = <String>{
      for (final String path in before.paths.intersection(after.paths))
        if ((before.changed.contains(path) || after.changed.contains(path)) &&
            _visible(path))
          path,
    };
    if (suspects.isEmpty) return const <CheckpointFileChange>[];
    final Map<String, List<int>> oldBytes = await readArchiveFiles(
      store,
      sessionId,
      fromTurn,
      suspects,
    );
    final Map<String, List<int>> newBytes = await readArchiveFiles(
      store,
      sessionId,
      toTurn,
      suspects,
    );
    return <CheckpointFileChange>[
      for (final String path in suspects)
        if (_bytesDiffer(oldBytes[path], newBytes[path]))
          CheckpointFileChange(path: path, status: 'modified'),
    ];
  }

  bool _visible(String path) =>
      checkpointReadablePath(path, store.projectRel, store.policy);
}

/// 两端都读到内容时才比较；任何一端缺失按「无变化」处理（避免把读失败
/// 报成内容变化）。
bool _bytesDiffer(List<int>? before, List<int>? after) {
  if (before == null || after == null) return false;
  if (before.length != after.length) return true;
  for (int index = 0; index < before.length; index++) {
    if (before[index] != after[index]) return true;
  }
  return false;
}

/// 某一轮的文件集与差量点名集合。
class _TurnState {
  const _TurnState({required this.paths, required this.changed});

  /// 该轮存在的全部路径。
  final Set<String> paths;

  /// 该轮差量里「相对 base 变化」的路径；turn 0 为空。
  final Set<String> changed;
}
