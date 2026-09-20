/// Tool 描述 → Intent 候选（部署时批量生成）。
library;

import 'dart:convert';

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';

import '../action.dart';
import '../intent.dart';
import 'intent_spec.dart';

/// 扫描工具表，为每个工具生成候选意图。
///
/// 这是**部署时工具**：部署方用它快速产出一份初始 `intents.json`，再人工审核。
/// 生成结果不注册、不落盘——调用方决定要不要写进配置。
class ToolIntentGenerator {
  /// 构造生成器。
  const ToolIntentGenerator({
    required this.tools,
    required this.llm,
    this.systemPrompt = kDefaultIntentSpecPrompt,
  });

  /// 工具来源。
  final ToolRegistry tools;

  /// 生成触发条件的模型。
  final LlmProvider llm;

  /// system prompt。
  final String systemPrompt;

  /// 为每个可见工具生成候选意图（按工具表顺序）。
  ///
  /// [only] 非空时只处理这些工具名。生成不出的工具被跳过（不产出空壳意图）。
  Future<List<Intent>> generate({Iterable<String>? only}) async {
    final Set<String>? wanted = only?.toSet();
    final List<Intent> intents = <Intent>[];
    for (final Map<String, Object?> schema in tools.describe()) {
      final String name = schema['name'] as String? ?? '';
      if (name.isEmpty || wanted?.contains(name) == false) continue;
      final Intent? intent = await _generateFrom(schema, name);
      if (intent != null) intents.add(intent);
    }
    return intents;
  }

  Future<Intent?> _generateFrom(
    Map<String, Object?> schema,
    String name,
  ) async {
    final LlmResult result = await llm.chat(<LlmMessage>[
      LlmMessage('system', systemPrompt),
      LlmMessage('user', _promptFor(schema, name)),
    ]);
    final IntentSpec spec = parseIntentSpec(result.content);
    if (spec.isEmpty) return null;
    return Intent(
      name: 'tool_$name',
      description: schema['description'] as String? ?? '',
      patterns: spec.compilePatterns(),
      examples: spec.examples,
      action: ToolAction(tool: name),
    );
  }
}

String _promptFor(Map<String, Object?> schema, String name) {
  final Object? parameters = schema['parameters'];
  return '工具名：$name\n'
      '工具描述：${schema['description'] ?? ''}\n'
      '参数：${jsonEncode(parameters ?? const <String, Object?>{})}\n\n'
      '请生成 2-3 个正则模式和 3-5 个示例语句，让用户能用自然语言触发这个工具。';
}
