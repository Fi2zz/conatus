/// 检查点时间线的可变状态：当前会话、轮次、串行链与解绑代数。
///
/// 从 [CheckpointManager] 拆出：编排（什么时候拍、恢复哪一轮）留在管理器，
/// 「谁在什么时候拥有这条时间线」独立在这里。管理器的类随之回到行数约束内。
library;

import 'checkpoint_chain.dart';

/// 一条检查点时间线的绑定状态与串行执行器。
class CheckpointTimeline {
  final CheckpointChain _chain = CheckpointChain();
  String? _sessionId;
  int _turn = 0;
  int _epoch = 0;

  /// 当前绑定的会话 id；未绑定为 `null`。
  String? get sessionId => _sessionId;

  /// 当前轮次（含 turn 0 初始快照）。
  int get turn => _turn;

  /// 解绑代数：[detach] 递增；排队时记下、执行时比对。
  int get epoch => _epoch;

  /// 链尾：`await` 它等于等所有已入队动作完成。
  Future<void> get settled => _chain.settled;

  /// 同步切换绑定（UI 立即可见），不碰存储。
  void bind(String sessionId, int turn) {
    _sessionId = sessionId;
    _turn = turn;
  }

  /// 解绑（幂等）：递增代数让在途 / 排队动作自行放弃。
  void detach() {
    _epoch++;
    _sessionId = null;
    _turn = 0;
  }

  /// 覆盖轮次（恢复 / 清空后同步用）。
  void setTurn(int turn) => _turn = turn;

  /// 轮次 +1 并返回新值（[CheckpointManager.recordTurn] 用）。
  int nextTurn() => ++_turn;

  /// [sessionId] 是否是当前绑定的会话。
  bool owns(String sessionId) => _sessionId == sessionId;

  /// 排队执行，不做代数检查（调用方自行判定）。
  Future<T> run<T>(Future<T> Function() action) => _chain.run(action);

  /// 入队即记代数；执行时代数已变（中途 [detach]）则跳过并返回 `null`。
  Future<T?> runGuarded<T>(Future<T> Function() action) {
    final int queued = _epoch;
    return _chain.run<T?>(() async => queued == _epoch ? await action() : null);
  }
}
