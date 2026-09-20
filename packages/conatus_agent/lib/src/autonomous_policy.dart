/// 自主运营的策略词汇：约束、边界与预算能力缝。
///
/// [AutonomousPolicy] 是 Capability Seam：预算、时间窗口、轮次上限、工具
/// 白名单/黑名单是硬约束，自主 Agent 不能绕过（见 HANDOFF-15 §2 设计原则）。
/// 缺省实现 [DefaultAutonomousPolicy]；预算输入由 [CostTracker] 提供，
/// 不提供时视为无预算限制。
library;

import 'agent_types.dart';

/// 自主策略。定义约束和边界。Capability Seam。
abstract class AutonomousPolicy {
  const AutonomousPolicy();

  /// 每日预算上限（美元）。
  double get dailyBudget;

  /// 时间窗口。null 表示全天。
  TimeWindow? get activeWindow;

  /// 可以自主执行的操作白名单；空集表示不限制。
  Set<String> get allowedActions;

  /// 必须人类确认的操作黑名单；空集表示无黑名单。
  Set<String> get requireApproval;

  /// 最大连续运行轮次。
  int get maxContinuousRounds;

  /// 单轮最大时长。
  Duration get maxTurnDuration;

  /// 是否需要人类在环。
  bool get requireHumanInLoop;

  /// 第一个违反本策略的工具名；无违规返回 null。
  ///
  /// 命中 [requireApproval] 黑名单，或 [allowedActions] 非空且未在白名单时
  /// 视为越界。自主 Runner 在每轮结束后据此判断是否需要人类介入。
  String? firstViolation(List<AgentStep> steps) {
    final Set<String> allowed = allowedActions;
    final Set<String> required = requireApproval;
    for (final AgentStep step in steps) {
      final String name = step.call.name;
      if (required.contains(name)) return name;
      if (allowed.isNotEmpty && !allowed.contains(name)) return name;
    }
    return null;
  }
}

/// 默认自主策略：无预算限制、全天、不限制工具、8 轮、单轮 5 分钟、
/// 不强制人类在环。
class DefaultAutonomousPolicy extends AutonomousPolicy {
  const DefaultAutonomousPolicy({
    this.dailyBudget = double.infinity,
    this.activeWindow,
    this.allowedActions = const <String>{},
    this.requireApproval = const <String>{},
    this.maxContinuousRounds = 8,
    this.maxTurnDuration = const Duration(minutes: 5),
    this.requireHumanInLoop = false,
  });

  @override
  final double dailyBudget;

  @override
  final TimeWindow? activeWindow;

  @override
  final Set<String> allowedActions;

  @override
  final Set<String> requireApproval;

  @override
  final int maxContinuousRounds;

  @override
  final Duration maxTurnDuration;

  @override
  final bool requireHumanInLoop;
}

/// 时间窗口。[start] / [end] 是 0-23 点内的一天时刻，支持跨午夜
/// （start > end，如 22:00-06:00）；[end] 允许到 48 小时内（覆盖
/// 「23 点开始、次日凌晨结束」的写法）。端点含。
class TimeWindow {
  TimeWindow({required this.start, required this.end}) {
    if (start.inHours < 0 || start.inHours >= 24) {
      throw ArgumentError.value(start, 'start', '必须是 0-23 点内的一天时刻');
    }
    if (end.inHours >= 48) {
      throw ArgumentError.value(end, 'end', '必须小于 48 小时');
    }
  }

  /// 开始时刻。
  final Duration start;

  /// 结束时刻。
  final Duration end;

  /// [time] 是否落在窗口内（含端点）。
  bool contains(DateTime time) {
    final Duration t = Duration(
        hours: time.hour,
        minutes: time.minute,
        seconds: time.second,
        milliseconds: time.millisecond);
    if (start <= end) return t >= start && t <= end;
    return t >= start || t <= end; // 跨午夜
  }

  /// [from] 之后窗口的下一次开始时刻。
  DateTime nextStart(DateTime from) {
    final DateTime candidate = DateTime(
      from.year,
      from.month,
      from.day,
      start.inHours % 24,
      start.inMinutes % 60,
    );
    if (candidate.isAfter(from)) return candidate;
    return candidate.add(const Duration(days: 1));
  }
}

/// 预算能力缝：提供当日累计成本（美元）。
///
/// 仓库尚无成本统计实现；本缝是 [AutonomousRunner] 预算检查的输入，
/// 不提供时视为无预算限制。实现方可从 LLM 用量或计费系统聚合。
abstract class CostTracker {
  /// 当日累计成本。
  double get todayCost;
}
