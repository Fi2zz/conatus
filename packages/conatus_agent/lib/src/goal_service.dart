/// goal 插件的服务端口。
///
/// [GoalService] 只存目标状态，不调度工作。工具、命令、续行驱动器是三个
/// 独立的消费端，都读同一份状态。状态机：active 可转 paused / blocked /
/// completed；paused 与 blocked 可 resume 回 active；clear 从任意状态转
/// cleared（终态）；completed 也是终态。
library;

import 'dart:async';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'goal.dart';

/// 目标服务。
abstract class GoalService {
  /// 当前会话的目标（至多一个）。无目标时返回 null。
  Goal? get current;

  /// 创建目标。已有非终态目标时抛 [GoalException]（`already_exists`）。
  Future<Goal> create(String text, {int? maxRounds});

  /// 编辑目标文本。仅 active / paused 状态可编辑。
  Future<Goal> edit(String text);

  /// 暂停。仅 active 可暂停。
  Future<Goal> pause();

  /// 恢复。paused / blocked 回到 active（清除阻塞原因）。
  Future<Goal> resume();

  /// 标记完成（终态）。走 approval 确认（若提供）。
  Future<Goal> complete();

  /// 标记阻塞。仅 active / paused 可阻塞。
  Future<Goal> block(String reason);

  /// 清除目标（终态）。走 approval 确认（若提供）。
  Future<Goal> clear();

  /// 递增轮次。超过 maxRounds 时自动 block。
  Future<void> advanceRound();

  /// 状态变更流。
  Stream<Goal> get changes;

  /// 从 Session 恢复状态。
  void restore(Session session);

  /// 释放资源。幂等。
  void dispose();
}

/// `ctx.goal`：当前上下文可见的目标服务。
extension GoalContext on Context {
  /// 取当前上下文可见的 [GoalService]（未提供时抛 [StateError]）。
  GoalService get goal => require<GoalService>('goal');
}
