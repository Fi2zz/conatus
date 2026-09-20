/// Skill 沉淀 → Intent 候选。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_llm/conatus_llm.dart';

import '../action.dart';
import '../intent.dart';
import '../router.dart';
import 'intent_spec.dart';

/// 技能沉淀与意图路由之间的桥。
///
/// `conatus_agent` 的 `SkillLibrary` 在 `maybeExtract` 返回非 null 时完成一次沉淀，
/// 调用方在该时机显式调用 [propose]（`SkillLibrary` 没有变更流，不做轮询）。
/// 产出的是**候选**意图——**不自动注册**，与技能「启用前需审批」的口径一致：
/// 模型生成的正则可能过宽，放它自动进路由器会污染整个快路径。
///
/// 已沉淀的技能本身就是 `ToolAction` 的目标，因此确认后这类输入直接跳过 Agent
/// Loop 的推理环节。
class SkillIntentBridge {
  /// 构造桥。
  SkillIntentBridge({
    required this.router,
    required this.llm,
    this.systemPrompt = kDefaultIntentSpecPrompt,
  });

  /// 目标路由器。
  final IntentRouter router;

  /// 生成触发条件的模型。
  final LlmProvider llm;

  /// system prompt。
  final String systemPrompt;

  final List<Intent> _pending = <Intent>[];

  /// 待确认的候选（按产出顺序）。
  List<Intent> get pending => List<Intent>.unmodifiable(_pending);

  /// 为一个已沉淀的技能生成候选意图；生成不出返回 null。
  Future<Intent?> propose(SkillTool skill) async {
    final IntentSpec spec = parseIntentSpec(await _ask(skill));
    if (spec.isEmpty) return null;
    final Intent candidate = Intent(
      name: 'skill_${skill.name}',
      description: skill.description,
      patterns: spec.compilePatterns(),
      examples: spec.examples,
      action: ToolAction(tool: skill.name),
    );
    _pending.add(candidate);
    return candidate;
  }

  /// 用户确认后注册；重名等注册失败会抛出，候选留在待确认里。
  Intent confirm(Intent candidate) {
    router.register(candidate);
    _pending.remove(candidate);
    return candidate;
  }

  /// 用户拒绝后丢弃。传回 [propose] 返回的同一个实例。
  void reject(Intent candidate) => _pending.remove(candidate);

  Future<String> _ask(SkillTool skill) async {
    final LlmResult result = await llm.chat(<LlmMessage>[
      LlmMessage('system', systemPrompt),
      LlmMessage('user', _promptFor(skill)),
    ]);
    return result.content;
  }
}

String _promptFor(SkillTool skill) {
  final String steps = <String>[
    for (final SkillStep step in skill.steps) step.toolName,
  ].join(' → ');
  return '能力名：${skill.name}\n'
      '描述：${skill.description}\n'
      '步骤：$steps\n\n'
      '请生成 2-3 个正则模式和 3-5 个示例语句，让用户能用自然语言触发它。';
}
