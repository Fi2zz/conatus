/// 目标优先级引擎。
///
/// [PriorityEngine] 是纯函数工具：给一组 [Goal] 按综合得分排序选下一个。
/// 得分 = importance * 0.5 + urgency * 0.3 + (1 - progress) * 0.2；
/// importance / urgency 缺省 5，可按 goal.id 覆盖；progress 由
/// round / maxRounds 推导。当前 [GoalService] 每会话至多一个目标，引擎
/// 为未来的多目标场景预留，Runner 用它记录每次选择的决策理由。
library;

import 'goal.dart';

/// 目标优先级。
class GoalPriority {
  const GoalPriority({
    required this.goal,
    required this.importance,
    required this.urgency,
    required this.progress,
  });

  /// 被评估的目标。
  final Goal goal;

  /// 重要性（1-10）。
  final int importance;

  /// 紧迫性（1-10）。
  final int urgency;

  /// 进度（0.0-1.0）。
  final double progress;

  /// 综合得分。
  double get score => importance * 0.5 + urgency * 0.3 + (1 - progress) * 0.2;
}

/// 优先级引擎。
class PriorityEngine {
  /// 选择下一个目标；空列表返回 null。
  ///
  /// 按 [scoreOf] 得分取最高者，同分保持列表原序（单趟扫描，严格大于才
  /// 替换，天然稳定）。
  Goal? selectNext(List<Goal> goals, {Map<String, int>? importance}) {
    Goal? best;
    double bestScore = double.negativeInfinity;
    for (final Goal goal in goals) {
      final double score = scoreOf(goal, importance: importance).score;
      if (score > bestScore) {
        bestScore = score;
        best = goal;
      }
    }
    return best;
  }

  /// 计算目标得分。[importance] / [urgency] 缺省 5，可按 goal.id 覆盖。
  GoalPriority scoreOf(
    Goal goal, {
    Map<String, int>? importance,
    Map<String, int>? urgency,
  }) {
    final double progress =
        goal.maxRounds <= 0 ? 0 : (goal.round / goal.maxRounds).clamp(0.0, 1.0);
    return GoalPriority(
      goal: goal,
      importance: importance?[goal.id] ?? 5,
      urgency: urgency?[goal.id] ?? 5,
      progress: progress,
    );
  }
}
