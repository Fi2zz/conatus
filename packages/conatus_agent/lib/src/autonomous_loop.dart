/// 自主运行的单轮迭代机制。
///
/// [AutonomousLoop] 承载 Runner 的循环主体：约束检查 → 目标选择 → 单轮执行 →
/// 审计/埋点 → 人类介入检查 → 目标推进。与 [DefaultAutonomousRunner] 的
/// 生命周期（run / stop / 结果装配）分离，便于独立演进与测试。时钟、睡眠与
/// 停止信号经函数注入，保证时间窗口相关行为可确定性测试。
library;

import 'dart:async';

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'agent_loop.dart';
import 'agent_types.dart';
import 'autonomous_policy.dart';
import 'autonomous_runner.dart';
import 'autonomous_seams.dart';
import 'goal.dart';
import 'goal_service.dart';

/// 自主运行的单轮迭代机制。
class AutonomousLoop {
  AutonomousLoop({
    required this.agent,
    required this.goal,
    required this.session,
    required AutonomousPolicy Function() policy,
    required AutonomousSeams seams,
    required DateTime Function() clock,
    required Future<void> Function(Duration) sleeper,
    required Completer<void> Function() stopSignal,
  })  : _policy = policy,
        _seams = seams,
        _clock = clock,
        _sleeper = sleeper,
        _stopSignal = stopSignal;

  /// 被驱动的 Agent Loop。
  final AgentLoop agent;

  /// 目标服务。
  final GoalService goal;

  /// 绑定的会话（审计归属与关闭检查）。
  final Session session;

  final AutonomousPolicy Function() _policy;
  final AutonomousSeams _seams;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _sleeper;
  final Completer<void> Function() _stopSignal;

  /// 执行一轮完整迭代。返回（停止原因, 成本增量）；停止原因非空时不推进目标。
  Future<(StopReason?, double)> iterate(
    List<AgentTurn> turns,
    List<String> advanced,
  ) async {
    final StopReason? early = await _earlyStop(turns.length);
    if (early != null) return (early, 0.0);
    final Goal active = goal.current!;
    final (AgentTurn turn, double costDelta) = await _runTurn();
    turns.add(turn);
    await _seams.auditTurn(active, turn, costDelta);
    _seams.emitTurn(active, turn, costDelta);
    final StopReason? human = await _humanCheck(turn);
    if (human != null) return (human, costDelta);
    final StopReason? advancedReason = await _advanceGoal(advanced);
    if (advancedReason != null) return (advancedReason, costDelta);
    return (null, costDelta);
  }

  /// 约束检查 + 目标状态检查；返回停止原因，null 表示可以继续。
  Future<StopReason?> _earlyStop(int turnCount) async {
    final StopReason? check = await _checkConstraints(turnCount);
    if (check != null) return check;
    return _goalStopReason(goal.current);
  }

  /// 预算 / 时间窗口 / 轮次上限检查。
  Future<StopReason?> _checkConstraints(int turnCount) async {
    final StopReason? hard = _hardStop(turnCount);
    if (hard != null) return hard;
    final TimeWindow? window = _policy().activeWindow;
    if (window == null || window.contains(_clock())) return null;
    return _windowDecision(window);
  }

  /// 会话 / 预算 / 轮次上限的硬停止检查。
  StopReason? _hardStop(int turnCount) {
    if (session.closed) return StopReason.manualStop;
    if (_seams.cost > _policy().dailyBudget) return StopReason.budgetExceeded;
    if (turnCount >= _policy().maxContinuousRounds) {
      return StopReason.maxRoundsReached;
    }
    return null;
  }

  /// 窗口外决策：nextStart 在今天则等待后继续，否则窗口结束。
  /// 等待被 [stop] 中断时直接返回 [StopReason.manualStop]。
  Future<StopReason?> _windowDecision(TimeWindow window) async {
    final DateTime now = _clock();
    final DateTime next = window.nextStart(now);
    if (!_isSameDay(now, next)) return StopReason.windowEnded;
    final bool interrupted = await _sleepUntil(next);
    return interrupted ? StopReason.manualStop : null;
  }

  /// 跑一轮：带单轮时长上限与成本增量统计。超时按空轮记录（迟到写入是
  /// 已知限制：底层 `agent.run` 仍在后台继续，其结果被丢弃）。
  Future<(AgentTurn, double)> _runTurn() async {
    final double before = _seams.cost;
    final Stopwatch watch = Stopwatch()..start();
    try {
      final AgentTurn turn = await agent
          .run(kAutonomousContinuationPrompt)
          .timeout(_policy().maxTurnDuration);
      return (turn, _seams.costDelta(before));
    } on TimeoutException {
      await _seams.audit('autonomous/turn_timeout', <String, Object?>{
        'durationMs': watch.elapsedMilliseconds,
      });
      return (
        const AgentTurn(
          reply: '',
          steps: <AgentStep>[],
          messages: <LlmMessage>[],
        ),
        0.0
      );
    }
  }

  /// 人类介入检查：工具越界或策略要求人在环时经审批确认；拒绝则停止。
  Future<StopReason?> _humanCheck(AgentTurn turn) async {
    final String? violation = _policy().firstViolation(turn.steps);
    if (violation != null) {
      final bool ok =
          await _seams.askApproval(violation, '自主运营使用了策略外工具 $violation');
      return ok ? null : StopReason.humanRequired;
    }
    if (!_policy().requireHumanInLoop) return null;
    final bool ok =
        await _seams.askApproval('autonomous/continue', '策略要求人类在环，是否允许自主继续？');
    return ok ? null : StopReason.humanRequired;
  }

  /// 推进目标轮次；目标被终态化/阻塞/暂停时返回停止原因，不再推进。
  Future<StopReason?> _advanceGoal(List<String> advanced) async {
    final Goal? after = goal.current;
    final StopReason? afterReason = _goalStopReason(after);
    if (afterReason != null) return afterReason;
    await goal.advanceRound();
    advanced.add(after!.id);
    return null;
  }

  /// 睡到 [until]；被 [stop] 中断时返回 true。
  Future<bool> _sleepUntil(DateTime until) async {
    final Duration wait = until.difference(_clock());
    if (wait <= Duration.zero) return false;
    await Future.any<void>(<Future<void>>[
      _sleeper(wait),
      _stopSignal().future,
    ]);
    return _stopSignal().isCompleted;
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// 目标状态检查：无目标/终态 → completed；阻塞/暂停 → humanRequired。
StopReason? _goalStopReason(Goal? current) {
  if (current == null || current.isTerminal) return StopReason.completed;
  if (current.status == GoalStatus.blocked) return StopReason.humanRequired;
  if (current.status == GoalStatus.paused) return StopReason.humanRequired;
  return null;
}
