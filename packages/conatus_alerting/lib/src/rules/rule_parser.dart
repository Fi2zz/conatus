/// 告警规则 JSON 解析（规则是数据，可从配置文件加载）。
library;

import 'package:conatus_agent/conatus_agent.dart';

import '../alert.dart';
import '../rule.dart';

/// 从声明式 JSON 解析规则集。
///
/// 支持两种条件：
///
/// - **字段比较**：`{event, field, operator, value}`（如
///   `{"event": "llm.request", "field": "durationMs", "operator": ">",
///   "value": 30000}`）；
/// - **窗口计数**：`{event, window, count, operator}`（如
///   `{"event": "tool.failed", "window": 60, "count": 5, "operator": ">"}`）。
class RuleParser {
  /// 从 JSON 解析规则。
  static List<AlertRule> parse(Map<String, Object?> json) {
    final List<Object?> rules = _listOf(json['rules']);
    return <AlertRule>[
      for (final Object? raw in rules)
        _parseRule(_mapOf(raw, 'rules[]')),
    ];
  }

  static AlertRule _parseRule(Map<String, Object?> json) {
    final String name = '${json['name'] ?? ''}';
    final AlertSeverity severity = _parseSeverity('${json['severity'] ?? ''}');
    final Duration cooldown = Duration(seconds: json['cooldown'] as int? ?? 300);
    final bool Function(TelemetryEvent, AlertContext) condition =
        _parseCondition(_mapOf(json['condition'], 'condition'));

    return AlertRule(
      name: name,
      severity: severity,
      cooldown: cooldown,
      description: json['description'] as String? ?? '',
      condition: condition,
    );
  }

  static bool Function(TelemetryEvent, AlertContext) _parseCondition(
    Map<String, Object?> json,
  ) {
    final String? eventName = json['event'] as String?;
    final int? window = json['window'] as int?;
    final int? count = json['count'] as int?;
    final String? field = json['field'] as String?;
    final String? op = json['operator'] as String?;
    final Object? value = json['value'];

    return (event, ctx) {
      if (eventName != null && event.name != eventName) return false;

      // 窗口计数条件
      if (window != null && count != null) {
        ctx.record(event.name);
        return ctx.countInWindow(event.name, Duration(seconds: window)) > count;
      }

      // 字段比较条件
      if (field != null && op != null) {
        return _compare(event.data[field], op, value);
      }

      return false;
    };
  }

  static bool _compare(Object? actual, String op, Object? expected) {
    if (actual is num && expected is num) {
      return switch (op) {
        '>' => actual > expected,
        '>=' => actual >= expected,
        '<' => actual < expected,
        '<=' => actual <= expected,
        '==' => actual == expected,
        '!=' => actual != expected,
        _ => false,
      };
    }
    if (op == '==') return actual == expected;
    if (op == '!=') return actual != expected;
    return false;
  }

  static AlertSeverity _parseSeverity(String name) =>
      AlertSeverity.values.asNameMap()[name] ?? AlertSeverity.warning;
}

List<Object?> _listOf(Object? value) =>
    value is List ? value : const <Object?>[];

Map<String, Object?> _mapOf(Object? value, String label) {
  if (value is Map) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        '${entry.key}': entry.value,
    };
  }
  throw ArgumentError.value(value, label, '期望 JSON 对象');
}
