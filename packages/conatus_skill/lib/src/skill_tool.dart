/// `skill` 工具：按名字把一段技能指令加载进对话。
library;

import 'dart:convert';

import 'package:conatus_foundation/conatus_foundation.dart';

import 'skill_content.dart';
import 'skill_registry.dart';
import 'skill_types.dart';

/// 加载技能正文的工具。
///
/// 只读、无副作用：结果就是一段 `<skill_content>` 文本，由 Agent Loop 正常写进
/// `tool/result` 事件，因此「模型可见即已记录」无需额外机制。
class SkillLoadTool extends Tool {
  /// 构造工具。
  const SkillLoadTool({required this.registry});

  /// 技能来源。
  final SkillRegistry registry;

  @override
  String get name => 'skill';

  @override
  String get description =>
      'Load the full instructions for an available skill. Call this with the '
      'exact skill name from the session skill catalog before acting on a task '
      'that names or clearly matches that skill.';

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string(
          'name',
          description: 'The exact skill name from the available skills list.',
          required: true,
        ),
      ];

  @override
  Future<ToolResult> call(ToolContext context) async {
    final String requested = context.str('name').trim();
    final String? rejection = _rejectionFor(requested);
    if (rejection != null) return _failure('SKILL_UNAVAILABLE', rejection);
    final SkillDefinition? definition = await registry.load(requested);
    if (definition == null) {
      return _failure('SKILL_UNKNOWN',
          'skill "$requested" is unknown or no longer available');
    }
    return ToolResult.success(
      renderSkillContent(definition),
      value: <String, Object?>{
        'name': definition.summary.name,
        'provider': definition.summary.provider,
        'content': definition.content,
      },
    );
  }

  /// 未命中快照的名字不算拒绝：交给 [SkillRegistry.load] 收敛成 `SKILL_UNKNOWN`。
  String? _rejectionFor(String requested) {
    if (!isSkillName(requested)) {
      return 'invalid skill name "$requested"';
    }
    final SkillSummary? summary = _summaryOf(requested);
    if (summary == null) return null;
    return summary.modelInvocable
        ? null
        : 'skill "$requested" is not available for model invocation';
  }

  SkillSummary? _summaryOf(String requested) {
    for (final SkillSummary summary in registry.available) {
      if (summary.name == requested) return summary;
    }
    return null;
  }

  ToolResult _failure(String code, String message) => ToolResult.failure(
        jsonEncode(<String, Object?>{'code': code, 'message': message}),
        error: ToolError(code, message),
      );
}
