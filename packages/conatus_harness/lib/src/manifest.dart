/// harness 制品的数据模型：可序列化、可 diff、可装配。
///
/// manifest 只声明「要什么」（指令段、档位、工具边界），不创建工具、不执行
/// 外部脚本；装配逻辑见 `apply_harness.dart`。
library;

import 'package:conatus_agent/conatus_agent.dart';

/// 一个 prompt 段：名字唯一，文本是纯字符串。
class PromptSectionSpec {
  const PromptSectionSpec({
    required this.name,
    required this.text,
    this.order = 0,
  });

  /// 从 JSON 还原。
  factory PromptSectionSpec.fromJson(Map<String, Object?> json) =>
      PromptSectionSpec(
        name: '${json['name'] ?? ''}',
        text: '${json['text'] ?? ''}',
        order: _intOf(json['order']),
      );

  /// 段名（重复注册会抛错）。
  final String name;

  /// 段文本。
  final String text;

  /// 排序权重（升序）。
  final int order;

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'text': text,
        'order': order,
      };
}

/// 一份 harness 制品。
class HarnessManifest {
  const HarnessManifest({
    required this.name,
    required this.profile,
    this.sections = const <PromptSectionSpec>[],
    this.allowedTools,
    this.forbiddenTools = const <String>{},
    this.metadata = const <String, Object?>{},
  });

  /// 从 JSON 还原；缺省字段用默认值。
  factory HarnessManifest.fromJson(Map<String, Object?> json) =>
      HarnessManifest(
        name: '${json['name'] ?? ''}',
        profile: _profileFromJson(_mapOf(json['profile'])),
        sections: <PromptSectionSpec>[
          for (final Object? item
              in (json['sections'] as List<Object?>?) ?? const <Object?>[])
            if (item is Map<String, Object?>) PromptSectionSpec.fromJson(item),
        ],
        allowedTools: _nullableSetOf(json['allowedTools']),
        forbiddenTools: _setOf(json['forbiddenTools']),
        metadata: _mapOf(json['metadata']),
      );

  /// 制品名。
  final String name;

  /// 执行档位（推理强度 + 工具预算）。
  final ExecutionProfile profile;

  /// 指令段。
  final List<PromptSectionSpec> sections;

  /// 工具白名单；`null` 表示不限制。
  final Set<String>? allowedTools;

  /// 永远拒绝的工具；优先于白名单。
  final Set<String> forbiddenTools;

  /// 标注信息，不参与装配。
  final Map<String, Object?> metadata;

  /// 序列化；集合按字典序输出，保证两次编码字节一致。
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'profile': _profileToJson(profile),
        'sections': <Map<String, Object?>>[
          for (final PromptSectionSpec section in sections) section.toJson(),
        ],
        'allowedTools': _sortedOrNull(allowedTools),
        'forbiddenTools': _sorted(forbiddenTools),
        'metadata': metadata,
      };
}

Map<String, Object?> _profileToJson(ExecutionProfile profile) =>
    <String, Object?>{
      'name': profile.name,
      'reasoningEffort': profile.reasoningEffort,
      'budget': <String, Object?>{
        'economyAfter': profile.budget.economyAfter,
        'strictAfter': profile.budget.strictAfter,
        'finalizeAfter': profile.budget.finalizeAfter,
        'strictEvery': profile.budget.strictEvery,
        'finalizeAllowed': _sorted(profile.budget.finalizeAllowed),
      },
    };

ExecutionProfile _profileFromJson(Map<String, Object?> json) {
  final Map<String, Object?> budget = _mapOf(json['budget']);
  return ExecutionProfile(
    name: '${json['name'] ?? 'standard'}',
    reasoningEffort: '${json['reasoningEffort'] ?? 'medium'}',
    budget: ToolBudgetPolicy(
      economyAfter: _intOf(budget['economyAfter'], 14),
      strictAfter: _intOf(budget['strictAfter'], 26),
      finalizeAfter: _intOf(budget['finalizeAfter'], 44),
      strictEvery: _intOf(budget['strictEvery'], 8),
      finalizeAllowed: budget.containsKey('finalizeAllowed')
          ? _setOf(budget['finalizeAllowed'])
          : const <String>{'read'},
    ),
  );
}

Map<String, Object?> _mapOf(Object? value) =>
    value is Map<String, Object?> ? value : const <String, Object?>{};

int _intOf(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

Set<String> _setOf(Object? value) => <String>{
      if (value is List<Object?>)
        for (final Object? item in value)
          if (item != null) '$item',
    };

Set<String>? _nullableSetOf(Object? value) =>
    value is List<Object?> ? _setOf(value) : null;

List<String> _sorted(Set<String> values) => values.toList()..sort();

List<String>? _sortedOrNull(Set<String>? values) =>
    values == null ? null : _sorted(values);
