/// 候选意图：LLM 生成的触发条件，动作由人绑定。
library;

import 'action.dart';
import 'bridges/intent_spec.dart';
import 'intent.dart';

/// 一条候选意图。
///
/// 与 [Intent] 的差别只在动作：模型不知道部署方有哪些工具、参数怎么填，因此候选
/// 只带「怎么触发」，注册前必须由人或部署方 [bind] 一个真实动作。
class IntentCandidate {
  /// 构造候选。
  const IntentCandidate({
    required this.name,
    required this.description,
    this.patterns = const <Pattern>[],
    this.examples = const <String>[],
  });

  /// 从 LLM 生成的触发条件构造；没有名字时返回 null（名字无法从内容可靠推断）。
  static IntentCandidate? fromSpec(IntentSpec spec) {
    final String? name = spec.name;
    if (name == null || spec.isEmpty) return null;
    return IntentCandidate(
      name: name,
      description: spec.description ?? '',
      patterns: spec.compilePatterns(),
      examples: spec.examples,
    );
  }

  /// 意图名。
  final String name;

  /// 意图描述。
  final String description;

  /// 正则模式。
  final List<Pattern> patterns;

  /// 示例语句。
  final List<String> examples;

  /// 绑定动作，成为可注册的 [Intent]。
  Intent bind(RoutedAction action) => Intent(
        name: name,
        description: description,
        patterns: patterns,
        examples: examples,
        action: action,
      );

  /// 序列化为 JSON（供人工审核时落盘）。
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'description': description,
        'patterns': <String>[
          for (final Pattern pattern in patterns)
            if (pattern is RegExp) pattern.pattern,
        ],
        'examples': examples,
      };
}
