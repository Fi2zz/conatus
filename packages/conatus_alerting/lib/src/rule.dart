/// 告警规则与判定上下文（滑动窗口统计 + 冷却状态）。
library;

import 'package:conatus_agent/conatus_agent.dart';

import 'alert.dart';

/// 告警规则。
///
/// 规则是**数据**：条件用 [condition] 声明式表达，可从 JSON 加载，不从代码
/// 硬编码。条件必须是纯函数：不修改外部状态，不抛异常（[Alerting] 会隔离
/// 单个规则异常，不影响其他规则）。
class AlertRule {
  /// 构造。
  const AlertRule({
    required this.name,
    required this.severity,
    required this.condition,
    this.cooldown = const Duration(minutes: 5),
    this.description = '',
  });

  /// 规则名字。唯一。
  final String name;

  /// 严重级别。
  final AlertSeverity severity;

  /// 条件函数。返回 true 表示触发。
  final bool Function(TelemetryEvent event, AlertContext ctx) condition;

  /// 冷却期。同一规则在冷却期内只触发一次。
  final Duration cooldown;

  /// 规则描述。
  final String description;

  /// 序列化为元信息（条件本身是代码，不序列化）。
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'severity': severity.name,
        'cooldown': cooldown.inSeconds,
        'description': description,
      };
}

/// 告警上下文。维护滑动窗口统计和冷却状态。
///
/// 每个 Alerting 实例持有一个 [AlertContext]。时间来源可注入（[now]），
/// 便于测试冷却期与窗口统计。
class AlertContext {
  /// 构造。[now] 缺省为系统时钟。
  AlertContext({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Map<String, List<DateTime>> _recent = <String, List<DateTime>>{};
  final Map<String, DateTime> _lastFired = <String, DateTime>{};
  final Map<String, Duration> _cooldowns = <String, Duration>{};

  /// 注册规则的冷却期。
  void registerCooldown(String ruleName, Duration cooldown) {
    _cooldowns[ruleName] = cooldown;
  }

  /// 是否在冷却中。
  bool isCoolingDown(String ruleName) {
    final DateTime? last = _lastFired[ruleName];
    if (last == null) return false;
    final Duration cooldown =
        _cooldowns[ruleName] ?? const Duration(minutes: 5);
    return _now().difference(last) < cooldown;
  }

  /// 标记已触发。
  void markFired(String ruleName) {
    _lastFired[ruleName] = _now();
  }

  /// 记录一个事件。
  void record(String key) {
    (_recent[key] ??= <DateTime>[]).add(_now());
  }

  /// 统计窗口内的事件数。
  int countInWindow(String key, Duration window) {
    final List<DateTime> times = _recent[key] ?? <DateTime>[];
    final DateTime cutoff = _now().subtract(window);
    return times.where((DateTime t) => t.isAfter(cutoff)).length;
  }

  /// 清理过期记录。定期调用，防止内存增长。
  void prune({Duration maxAge = const Duration(hours: 1)}) {
    final DateTime cutoff = _now().subtract(maxAge);
    for (final String key in _recent.keys.toList()) {
      _recent[key]!.removeWhere((DateTime t) => t.isBefore(cutoff));
      if (_recent[key]!.isEmpty) _recent.remove(key);
    }
  }
}
