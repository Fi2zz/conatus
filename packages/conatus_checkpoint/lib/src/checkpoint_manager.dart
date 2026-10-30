/// 每会话检查点管理器：轮次计数、绑定/解绑、`/rewind` 与 undo/redo 编排。
///
/// 服务键由宿主决定（惯用 `'checkpointManager'`）；绑定会话用 [bind]
/// （接管已有时间线）或 [reset]（重建），每轮收口后 [recordTurn]；[rewind]
/// 只回滚工作区文件、不动会话与对话（v1 语义：对话切点由调用方按
/// [CheckpointRewindResult.lastEventId] 自行 fork）。
library;

import 'checkpoint_changes.dart';
import 'checkpoint_options.dart';
import 'checkpoint_restore_ops.dart';
import 'checkpoint_snapshots.dart';
import 'checkpoint_store.dart';
import 'checkpoint_timeline.dart';
import 'checkpoint_types.dart';

/// 每会话检查点管理器。
class CheckpointManager {
  CheckpointManager({
    required CheckpointStore store,
    required CheckpointOptions options,
  })  : _store = store,
        _options = options;

  final CheckpointStore _store;
  final CheckpointOptions _options;
  final CheckpointTimeline _timeline = CheckpointTimeline();

  /// 当前绑定的会话 id；未绑定为 `null`。
  String? get sessionId => _timeline.sessionId;

  /// 当前轮次（含 turn 0 初始快照）。
  int get turn => _timeline.turn;

  /// 是否启用（[CheckpointOptions.enabled]）。
  bool get enabled => _options.enabled;

  /// 绑定会话：接管已有检查点，无历史时写初始快照（turn 0）。失败返回错误说明。
  ///
  /// 与 [reset] 的区别就是「接管」：`--session` 重开会话、或在原会话上做
  /// redo 时，旧基线/差量必须留着——清掉就没有可回的点。轮次的最终判定在
  /// 串行链上（先给 UI 一个同步读到的即时值）：有快照在飞时等它落盘再取
  /// 最大轮次，否则会少认一轮并把它覆盖掉。
  Future<String?> bind(String sessionId, {String? lastEventId}) {
    _timeline.bind(sessionId, latestTurnOrZero(_store, sessionId));
    return _timeline.runGuarded<String?>(
      () => enabled
          ? bindSnapshot(_timeline, _store, sessionId, lastEventId: lastEventId)
          : Future<String?>.value(),
    );
  }

  /// 等所有在途快照落盘（含已排队但还没跑完的 [recordTurn]）。
  ///
  /// [reset] / [bind] 会立即返回（大工作区的基线可达数十秒），需要「此刻
  /// 的工作区已经拍下来了」的调用方（undo / redo / diff）先 await 它。
  Future<void> flush() => _timeline.settled;

  /// 绑定会话并**重建**时间线：轮次归 0 并写初始快照（turn 0）。
  /// 失败返回错误说明。
  ///
  /// 重绑即新时间线：会话已有检查点时先清空（旧 base/差量一并移除），
  /// 避免旧差量叠在新 base 上合成从未存在过的混合状态。要接管已有时间线
  /// 请用 [bind]。立即返回（不 await 快照落盘），让 UI 先就绪。
  Future<String?> reset(String sessionId, {String? lastEventId}) {
    _timeline.bind(sessionId, 0);
    return _timeline.runGuarded<String?>(
      () => enabled
          ? writeBaseSnapshot(_store, sessionId, lastEventId: lastEventId)
          : Future<String?>.value(),
    );
  }

  /// 解绑会话（幂等）。递增代数让在途的基线快照自行放弃。
  void detach() => _timeline.detach();

  /// 每轮收口后调用：轮次 +1 并快照。失败返回错误说明（不抛出）。
  ///
  /// 与 [reset] 共用串行链：本轮的差量一定晚于基线落盘。
  Future<String?> recordTurn({String? lastEventId}) =>
      _timeline.runGuarded<String?>(
        () => recordSnapshot(
          _timeline,
          _store,
          enabled,
          lastEventId: lastEventId,
        ),
      );

  /// 任意会话的检查点摘要（删除确认等只读场景用，不要求已绑定）。
  List<CheckpointInfo> listFor(String sessionId) =>
      enabled ? _store.list(sessionId) : const <CheckpointInfo>[];

  /// 可用检查点摘要（轮次升序，含有效文件数）。
  List<CheckpointInfo> list() {
    final String? id = _timeline.sessionId;
    if (id == null || !enabled) return const <CheckpointInfo>[];
    return _store.list(id);
  }

  /// 回滚 [steps] 轮（缺省 1）：目标 = 当前轮次 - steps，钳制到最早检查点。
  ///
  /// 无检查点（未启用 / 无历史）返回 `null`。恢复不动检查点目录，可反复回滚。
  Future<CheckpointRewindResult?> rewind(int steps) {
    final String? id = _timeline.sessionId;
    if (id == null || !enabled) return Future<CheckpointRewindResult?>.value();
    return _timeline.runGuarded<CheckpointRewindResult?>(
      () => rewindCheckpoint(_store, id, steps),
    );
  }

  /// 恢复到任意会话的 [turn] 轮（undo / redo 用）；轮次不存在返回 `null`。
  ///
  /// 与 [rewind] 的区别是目标显式给出、不做「往回 N 轮」的钳制。绑定同一
  /// 会话时同步 [_timeline] 的轮次（重做后再撤销才落在对的轮次上）。
  Future<CheckpointRewindResult?> restoreTo(String sessionId, int turn) {
    if (!enabled) return Future<CheckpointRewindResult?>.value();
    return _timeline.runGuarded<CheckpointRewindResult?>(() async {
      final CheckpointRewindResult? result = await restoreCheckpoint(
        _store,
        sessionId,
        turn,
      );
      if (result != null && _timeline.owns(sessionId)) {
        _timeline.setTurn(turn);
      }
      return result;
    });
  }

  /// 清空某会话的全部检查点（幂等），在串行链上执行。
  ///
  /// 绑定同一会话时轮次归 0——清空后就不存在「第 N 轮」了，留在旧数字上
  /// 会让 UI 与后续差量都指向不存在的基线。
  Future<void> clearSession(String sessionId) {
    final int queued = _timeline.epoch;
    return _timeline.run(() async {
      if (queued != _timeline.epoch) return;
      await _store.clearSession(sessionId);
      if (_timeline.owns(sessionId)) _timeline.setTurn(0);
    });
  }

  /// 读某会话某轮的清单（`/diff` 的 turn 0 需要枚举文件）；透传给存储。
  Future<CheckpointManifest> loadManifest(String sessionId, int turn) =>
      _store.loadManifest(sessionId, turn);

  /// 路径是否可见于 `/diff`（统一走存储的排除面：只读目录 / 凭据 / build）。
  bool showsDiffPath(String path) => _store.readablePath(path);

  /// 读某会话某轮里 [path] 的内容（`/diff` 数据源）；透传给存储。
  Future<List<int>?> readFile(String sessionId, int turn, String path) =>
      _store.readFile(sessionId, turn, path);

  /// 批量读某会话某轮里若干路径的内容（`/diff` 数据源）；透传给存储。
  Future<Map<String, List<int>>> readFiles(
    String sessionId,
    int turn,
    Iterable<String> paths,
  ) =>
      _store.readFiles(sessionId, turn, paths);

  /// 两轮之间的文件变化（`/diff` 数据源）；透传给存储。
  Future<List<CheckpointFileChange>> changesBetween(
    String sessionId,
    int fromTurn,
    int toTurn,
  ) =>
      _store.changesBetween(sessionId, fromTurn, toTurn);
}
