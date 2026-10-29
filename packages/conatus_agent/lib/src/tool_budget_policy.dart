/// 工具预算的阶段策略：经济 → 收敛 → 收口。
///
/// 策略是纯数据 + 纯函数，不持有状态；计数由 `tool_budget_hooks.dart` 的中间件
/// 维护。所有阶段阈值设 0 即关闭该阶段（`finalizeAfter: 0` 表示不限工具数）。
library;

/// 一次工具调用所处阶段。
enum ToolBudgetStage {
  /// 正常探索。
  normal,

  /// 经济阶段：要求批量检查、禁止重复读。
  economy,

  /// 收敛阶段：只查与当前失败或交付物直接相关的证据。
  strict,

  /// 收口阶段：拒绝白名单之外的新调用。
  finalize,
}

/// 阶段阈值与收口白名单。
class ToolBudgetPolicy {
  const ToolBudgetPolicy({
    this.economyAfter = 14,
    this.strictAfter = 26,
    this.finalizeAfter = 44,
    this.strictEvery = 8,
    this.finalizeAllowed = const <String>{'read'},
  });

  /// 第几次调用起进入经济阶段；0 表示不启用。
  final int economyAfter;

  /// 第几次调用起进入收敛阶段；0 表示不启用。
  final int strictAfter;

  /// 超过第几次调用后拒绝新调用；0 表示不限制。
  final int finalizeAfter;

  /// 收敛阶段提醒的间隔（次）。
  final int strictEvery;

  /// 收口阶段仍放行的工具名。
  final Set<String> finalizeAllowed;

  /// 第 [count] 次调用所在的阶段。
  ToolBudgetStage stageOf(int count) {
    if (finalizeAfter > 0 && count > finalizeAfter) {
      return ToolBudgetStage.finalize;
    }
    if (strictAfter > 0 && count >= strictAfter) {
      return ToolBudgetStage.strict;
    }
    if (economyAfter > 0 && count >= economyAfter) {
      return ToolBudgetStage.economy;
    }
    return ToolBudgetStage.normal;
  }

  /// 第 [count] 次调用后应追加的提醒；不需要提醒时返回 `null`。
  String? note(int count) {
    if (economyAfter > 0 && count == economyAfter) {
      return '经济阶段开始：批量执行相互独立的检查，抑制过程叙述，不重复读取'
          '未变化的内容。不要以省略验证或最终状态复核来换取更少调用。';
    }
    if (strictAfter > 0 && count >= strictAfter && _due(count)) {
      return '收敛阶段：停止广泛探索，只检查与当前失败或交付物直接相关的证据。'
          '若仍有具体失败、无法解释的不稳定或已被改动而未复核的交付物，先修复再收口；'
          '然后复核一次精确路径、接口、行为与最终状态。';
    }
    return null;
  }

  /// 收口阶段拒绝该工具时返回可读理由；放行时返回 `null`。
  String? denialFor(int count, String toolName) {
    if (stageOf(count) != ToolBudgetStage.finalize) return null;
    if (finalizeAllowed.contains(toolName)) return null;
    return '工具调用预算已用尽（收口阶段仍允许：'
        '${finalizeAllowed.join('、')}）。保留当前产物，停止调用工具，'
        '基于已有证据给出最佳答复。';
  }

  bool _due(int count) =>
      count == strictAfter ||
      (strictEvery > 0 && (count - strictAfter) % strictEvery == 0);
}
