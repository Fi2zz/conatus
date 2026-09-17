/// goal 续行驱动器。
///
/// 这是 Goal 与 Plan Mode 最大的不同点：Goal 需要**驱动 Agent 继续工作**，
/// 而不是等用户输入。[GoalRoundDriver] 在 Agent Loop 每轮收口后被询问是否
/// 继续：active 且未达轮次上限 → 递增轮次再跑一轮；paused / 无目标 → 等待；
/// 终态 / 阻塞 / 达到轮次上限（自动 block）→ 停止。经 `ctx.inject` 装配
/// （见 `goal_provider.dart` 的 `_attachDriver`）。
library;

import 'package:conatus_core/conatus_core.dart';
import 'agent_cancel.dart';
import 'agent_loop.dart';
import 'agent_types.dart';
import 'goal.dart';
import 'goal_service.dart';

/// 续行提示：驱动器代用户注入的下一轮输入。
const String kGoalContinuationPrompt = '[系统] 继续推进当前目标。';

/// 续行决策。
enum GoalContinuation {
  /// 继续下一轮。
  proceed,

  /// 等待用户输入。
  wait,

  /// 已停止（终态、阻塞或达到轮次上限）。
  stop,
}

/// `ctx.goalRoundDriver`：当前上下文可见的续行驱动器。
extension GoalRoundDriverContext on Context {
  /// 取当前上下文可见的 [GoalRoundDriver]（未提供时抛 [StateError]）。
  GoalRoundDriver get goalRoundDriver =>
      require<GoalRoundDriver>('goalRoundDriver');
}

/// Goal 续行驱动器：读 [GoalService] 状态，驱动 [AgentLoop] 续行。
class GoalRoundDriver {
  /// [agent] 被续行的 Agent Loop；[goal] 读取的目标服务。
  GoalRoundDriver({required this.goal, required this.agent});

  /// 目标服务。
  final GoalService goal;

  /// 被续行的 Agent Loop。
  final AgentLoop agent;

  /// 判断是否应该继续。
  Future<GoalContinuation> shouldContinue() async {
    final Goal? current = goal.current;
    if (current == null) return GoalContinuation.wait;
    return switch (current.status) {
      GoalStatus.completed ||
      GoalStatus.cleared ||
      GoalStatus.blocked =>
        GoalContinuation.stop,
      GoalStatus.paused => GoalContinuation.wait,
      GoalStatus.active => await _activeDecision(current),
    };
  }

  /// 推进一轮。由 Agent Loop 在每轮收口后调用；返回 `null` 表示停止续行。
  Future<AgentTurn?> advance({AgentCancel? cancel}) async {
    if (await shouldContinue() != GoalContinuation.proceed) return null;
    await goal.advanceRound();
    if (await shouldContinue() != GoalContinuation.proceed) return null;
    return agent.run(kGoalContinuationPrompt, cancel: cancel);
  }

  Future<GoalContinuation> _activeDecision(Goal current) async {
    if (current.round < current.maxRounds) return GoalContinuation.proceed;
    await goal.block(kGoalRoundLimitReason);
    return GoalContinuation.stop;
  }
}
