/// goal 的默认实现。
///
/// [DefaultGoalService] 只负责目标状态机：每会话至多一个当前目标，状态变更
/// 整值替换（写一条 `goal/changed` 事件，恢复时折叠最后一条），fork 不继承。
/// 持久化、prompt 注入、审批确认、埋点全部委托 [GoalSeams]。装配走
/// `goal_provider.dart` 的 [provideGoal]。
library;

import 'dart:async';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'approval.dart';
import 'goal.dart';
import 'goal_seams.dart';
import 'goal_service.dart';
import 'telemetry.dart';

/// [GoalService] 的默认实现。
class DefaultGoalService implements GoalService {
  /// 各 seam 显式传入优先；缺省时从 [ctx] 惰性解析；再缺省则降级
  /// （不持久化 / 无提示词注入 / 自动批准 / 无埋点）。
  DefaultGoalService({
    Session? session,
    SystemPrompt? prompt,
    Approval? approval,
    Telemetry? telemetry,
    Context? ctx,
    this.defaultMaxRounds = 256,
  }) : _seams = GoalSeams(
            session: session,
            prompt: prompt,
            approval: approval,
            telemetry: telemetry,
            ctx: ctx) {
    final Session? resolved = _seams.resolveSession();
    if (resolved != null) restore(resolved);
  }

  /// 新建目标缺省的轮次上限。
  final int defaultMaxRounds;

  final GoalSeams _seams;
  Goal? _stored;
  bool _disposed = false;

  final StreamController<Goal> _changes = StreamController<Goal>.broadcast();

  @override
  Goal? get current {
    final Goal? goal = _stored;
    if (goal == null || goal.status == GoalStatus.cleared) return null;
    return goal;
  }

  @override
  Stream<Goal> get changes => _changes.stream;

  @override
  Future<Goal> create(String text, {int? maxRounds}) async {
    final Goal? existing = current;
    if (existing != null && !existing.isTerminal) {
      throw const GoalException('already_exists', '当前已有进行中的目标，请先完成或清除。');
    }
    final DateTime now = DateTime.now();
    final Goal goal = Goal(
      id: 'goal-${now.microsecondsSinceEpoch}',
      text: text,
      status: GoalStatus.active,
      round: 0,
      maxRounds: maxRounds ?? defaultMaxRounds,
      createdAt: now,
      updatedAt: now,
      revisions: <GoalRevision>[GoalRevision(text: text, revisedAt: now)],
    );
    _commit(goal, 'goal.created');
    return goal;
  }

  @override
  Future<Goal> edit(String text) async {
    final Goal goal = _requireLiveGoal(current, '编辑');
    if (goal.status == GoalStatus.blocked) {
      throw const GoalException('invalid_status', '目标处于阻塞状态，恢复后才能编辑。');
    }
    final DateTime now = DateTime.now();
    final Goal next = goal.copyWith(
      text: text,
      updatedAt: now,
      revisions: <GoalRevision>[
        ...goal.revisions,
        GoalRevision(text: text, revisedAt: now),
      ],
    );
    _commit(next, 'goal.edited');
    return next;
  }

  @override
  Future<Goal> pause() async {
    final Goal goal = _requireLiveGoal(current, '暂停');
    if (goal.status != GoalStatus.active) {
      throw const GoalException('invalid_status', '仅活动的目标可暂停。');
    }
    final Goal next =
        goal.copyWith(status: GoalStatus.paused, updatedAt: DateTime.now());
    _commit(next, 'goal.paused');
    return next;
  }

  @override
  Future<Goal> resume() async {
    final Goal goal = _requireLiveGoal(current, '恢复');
    final bool resumable =
        goal.status == GoalStatus.paused || goal.status == GoalStatus.blocked;
    if (!resumable) {
      throw const GoalException('invalid_status', '仅暂停或阻塞的目标可恢复。');
    }
    final Goal next = goal.copyWith(
      status: GoalStatus.active,
      blockReason: null,
      updatedAt: DateTime.now(),
    );
    _commit(next, 'goal.resumed');
    return next;
  }

  @override
  Future<Goal> block(String reason) async {
    final Goal goal = _requireLiveGoal(current, '阻塞');
    final Goal next = goal.copyWith(
      status: GoalStatus.blocked,
      blockReason: reason,
      updatedAt: DateTime.now(),
    );
    _commit(next, 'goal.blocked');
    return next;
  }

  @override
  Future<Goal> complete() async {
    final Goal goal = _requireLiveGoal(current, '完成');
    await _seams.confirm('complete_goal', '完成当前目标会结束长期推进，确认？', goal);
    final Goal next =
        goal.copyWith(status: GoalStatus.completed, updatedAt: DateTime.now());
    _commit(next, 'goal.completed');
    return next;
  }

  @override
  Future<Goal> clear() async {
    final Goal goal = _requireAnyGoal(_stored, '清除');
    await _seams.confirm('clear_goal', '清除当前目标会丢失所有进度，确认？', goal);
    final Goal next =
        goal.copyWith(status: GoalStatus.cleared, updatedAt: DateTime.now());
    _commit(next, 'goal.cleared');
    return next;
  }

  @override
  Future<void> advanceRound() async {
    final Goal goal = _requireLiveGoal(current, '推进');
    if (goal.status != GoalStatus.active) {
      throw const GoalException('invalid_status', '仅活动的目标可推进轮次。');
    }
    final DateTime now = DateTime.now();
    if (goal.round + 1 >= goal.maxRounds) {
      _commit(
        goal.copyWith(
          status: GoalStatus.blocked,
          round: goal.maxRounds,
          blockReason: kGoalRoundLimitReason,
          updatedAt: now,
        ),
        'goal.blocked',
      );
      return;
    }
    _commit(
        goal.copyWith(round: goal.round + 1, updatedAt: now), 'goal.advanced');
  }

  @override
  void restore(Session session) {
    _seams.bindSession(session);
    _stored = restoreGoalState(session);
    _seams.syncSection(() => current);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _seams.detachSection();
    unawaited(_changes.close());
  }

  void _commit(Goal next, String eventName) {
    if (_disposed) return;
    _stored = next;
    _seams.appendEvent(next);
    _seams.syncSection(() => current);
    _changes.add(next);
    _seams.emit(eventName, next);
  }
}

/// 取当前目标；无目标或已终态时抛 [GoalException]（`invalid_status`）。
Goal _requireLiveGoal(Goal? goal, String action) {
  if (goal == null || goal.isTerminal) {
    throw GoalException('invalid_status', '当前没有可$action的目标。');
  }
  return goal;
}

/// 取存储目标（含终态）；无目标时抛 [GoalException]（`no_goal`）。
Goal _requireAnyGoal(Goal? goal, String action) {
  if (goal == null) {
    throw GoalException('no_goal', '当前没有可$action的目标。');
  }
  return goal;
}
