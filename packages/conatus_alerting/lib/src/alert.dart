/// 告警值对象：一条「什么不对劲」的记录。
library;

import 'package:conatus_agent/conatus_agent.dart';

/// 告警严重级别。
enum AlertSeverity {
  /// 信息。无需用户干预，仅记录。
  info,

  /// 警告。用户应知晓，但不阻塞。
  warning,

  /// 严重。需要用户介入。
  critical,
}

/// 一条告警。
class Alert {
  /// 构造。
  const Alert({
    required this.id,
    required this.rule,
    required this.severity,
    required this.event,
    required this.firedAt,
    this.sessionId,
    this.goalId,
    this.context = const <String, Object?>{},
  });

  /// 告警唯一 ID。
  final String id;

  /// 触发规则的名字。
  final String rule;

  /// 严重级别。
  final AlertSeverity severity;

  /// 触发事件。
  final TelemetryEvent event;

  /// 触发时间。
  final DateTime firedAt;

  /// 关联的 Session ID。
  final String? sessionId;

  /// 关联的 Goal ID。
  final String? goalId;

  /// 附加上下文。
  final Map<String, Object?> context;

  /// 人类可读的摘要。
  String get summary {
    switch (rule) {
      case 'llm-slow':
        return 'LLM 调用耗时 ${event.data['durationMs']}ms';
      case 'tool-slow':
        return '工具 ${event.data['tool']} 耗时 ${event.data['durationMs']}ms';
      case 'tool-failures':
        return '最近 1 分钟工具失败 ${event.data['count']} 次';
      case 'session-budget':
        return 'Session 成本已达 \$${event.data['sessionCost']}';
      case 'agent-loop':
        return 'Agent 轮次超过 ${event.data['maxSteps']} 步';
      default:
        return event.name;
    }
  }

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'rule': rule,
        'severity': severity.name,
        'event': event.toJson(),
        'firedAt': firedAt.toIso8601String(),
        if (sessionId != null) 'sessionId': sessionId,
        if (goalId != null) 'goalId': goalId,
        'context': context,
        'summary': summary,
      };

  /// 从 JSON 反序列化。
  factory Alert.fromJson(Map<String, Object?> json) => Alert(
        id: '${json['id'] ?? ''}',
        rule: '${json['rule'] ?? ''}',
        severity: AlertSeverity.values.asNameMap()['${json['severity']}'] ??
            AlertSeverity.warning,
        event: _eventFromJson(_mapOf(json['event'])),
        firedAt: _parseDate(json['firedAt']) ?? DateTime.now(),
        sessionId: json['sessionId'] as String?,
        goalId: json['goalId'] as String?,
        context: _mapOf(json['context']),
      );
}

TelemetryEvent _eventFromJson(Map<String, Object?> json) {
  final Map<String, Object?> data = <String, Object?>{};
  for (final MapEntry<String, Object?> entry in json.entries) {
    if (entry.key == 'name' || entry.key == 'time') continue;
    data[entry.key] = entry.value;
  }
  return TelemetryEvent(
    '${json['name'] ?? ''}',
    data: data,
    time: _parseDate(json['time']) ?? DateTime.now(),
  );
}

Map<String, Object?> _mapOf(Object? value) => value is Map
    ? <String, Object?>{for (final MapEntry<Object?, Object?> e in value.entries) '${e.key}': e.value}
    : const <String, Object?>{};

DateTime? _parseDate(Object? raw) =>
    raw == null ? null : DateTime.tryParse('$raw');
