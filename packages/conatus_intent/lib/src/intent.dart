/// 一个意图：触发条件（正则 / 示例）与命中后执行的动作。
library;

import 'action.dart';
import 'errors.dart';
import 'json_helpers.dart';

/// 一个意图。
class Intent {
  /// 构造意图。
  const Intent({
    required this.name,
    required this.description,
    required this.action,
    this.patterns = const <Pattern>[],
    this.examples = const <String>[],
    this.embedding,
    this.priority = 0,
  });

  /// 从 JSON 还原。
  ///
  /// 动作由 [actionBuilder] 解析——类型层不认识处理器表与技能注册表，配置语义
  /// 留在 `IntentLoader` 里。
  factory Intent.fromJson(
    Map<String, Object?> json, {
    required RoutedAction Function(Map<String, Object?> json) actionBuilder,
  }) {
    final Object? action = json['action'];
    if (action is! Map) {
      throw const IntentException('missing-field', '缺少必填字段: action');
    }
    return Intent(
      name: requiredString(json, 'name'),
      description: json['description'] as String? ?? '',
      action: actionBuilder(Map<String, Object?>.from(action)),
      patterns: <Pattern>[
        for (final String source in optionalStringList(json, 'patterns'))
          RegExp(source),
      ],
      examples: optionalStringList(json, 'examples'),
      embedding: nullableDoubleList(json, 'embedding'),
      priority: json['priority'] as int? ?? 0,
    );
  }

  /// 意图名。唯一。
  final String name;

  /// 意图描述。
  final String description;

  /// 路由动作。
  final RoutedAction action;

  /// 正则模式。命中即执行。
  final List<Pattern> patterns;

  /// 示例语句。用于生成嵌入。
  final List<String> examples;

  /// 预计算的嵌入。设备端不生成，由构建时或云端提供。
  final List<double>? embedding;

  /// 优先级。数字越大越优先。默认 0。
  final int priority;

  /// 是否只有正则。
  bool get hasPatterns => patterns.isNotEmpty;

  /// 是否可向量匹配。
  bool get hasVector => examples.isNotEmpty;

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'description': description,
        if (patterns.isNotEmpty)
          'patterns': <String>[
            for (final Pattern pattern in patterns) _patternSource(pattern),
          ],
        if (examples.isNotEmpty) 'examples': examples,
        if (embedding != null) 'embedding': embedding,
        if (priority != 0) 'priority': priority,
        'action': action.toJson(),
      };
}

String _patternSource(Pattern pattern) {
  if (pattern is RegExp) return pattern.pattern;
  throw IntentException(
    'not-serializable',
    '${pattern.runtimeType} 不是 RegExp，无法序列化',
  );
}
