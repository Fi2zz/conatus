/// 约束：流程启动前检查，返回 null 表示满足，否则返回原因。
library;

import 'package:conatus_agent/conatus_agent.dart';

/// 约束检查上下文。
class ConstraintContext {
  ConstraintContext({
    this.now = DateTime.now,
    this.permissions,
    this.runningMutexes = const <String>{},
  });

  /// 当前时刻来源；测试可注入。
  final DateTime Function() now;

  /// 当前授予的权限；null 表示权限体系未启用（缺省放行）。
  final Set<String>? permissions;

  /// 正在运行的互斥 key 集合。
  final Set<String> runningMutexes;
}

/// 约束。
sealed class Constraint {
  const Constraint();

  /// 检查是否满足。返回 null 表示满足，否则返回原因。
  Future<String?> check(ConstraintContext ctx);
}

/// 预算约束。当日成本超过上限时阻塞；无成本跟踪时放行。
class BudgetConstraint extends Constraint {
  const BudgetConstraint({required this.dailyMax, this.costTracker});

  final double dailyMax;
  final CostTracker? costTracker;

  @override
  Future<String?> check(ConstraintContext ctx) async {
    final tracker = costTracker;
    if (tracker == null) return null;
    if (tracker.todayCost > dailyMax) {
      return '预算超限：${tracker.todayCost} > $dailyMax';
    }
    return null;
  }
}

/// 时间窗口约束。当前时刻不在窗口内时阻塞。
class TimeWindowConstraint extends Constraint {
  const TimeWindowConstraint(this.window);

  final TimeWindow window;

  @override
  Future<String?> check(ConstraintContext ctx) async {
    if (!window.contains(ctx.now())) return '不在时间窗口内';
    return null;
  }
}

/// 权限约束。缺少任一所需权限时阻塞；权限体系未启用时放行。
class PermissionConstraint extends Constraint {
  const PermissionConstraint({required this.requiredPermissions});

  final Set<String> requiredPermissions;

  @override
  Future<String?> check(ConstraintContext ctx) async {
    final granted = ctx.permissions;
    if (granted == null) return null;
    final missing = requiredPermissions.difference(granted);
    if (missing.isNotEmpty) return '缺少权限：$missing';
    return null;
  }
}

/// 互斥约束。同一 [mutexKey] 已有运行中流程时阻塞。
class MutexConstraint extends Constraint {
  const MutexConstraint(this.mutexKey);

  final String mutexKey;

  @override
  Future<String?> check(ConstraintContext ctx) async {
    if (ctx.runningMutexes.contains(mutexKey)) {
      return '互斥流程正在运行：$mutexKey';
    }
    return null;
  }
}
