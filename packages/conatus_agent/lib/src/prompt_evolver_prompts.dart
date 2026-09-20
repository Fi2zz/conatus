/// prompt-evolver 的 LLM prompt 层：失败模式分析与变体生成。
library;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'prompt_variant.dart';

/// 用 LLM 分析低质量轨迹，提取共性失败模式。
Future<String> analyzeFailurePatterns(
  LlmProvider llm,
  List<SessionEvent> traces,
) async {
  final String prompt = '''
以下是 Agent 执行失败的轨迹。请分析共性失败模式：

${traces.map(_summarizeEvent).join('\n')}

请提取 1-3 个共性失败模式，每个包含：
1. 模式描述
2. 典型表现
3. 可能的 prompt 改进方向
''';
  final LlmResult result = await llm.chat(<LlmMessage>[
    const LlmMessage('system', '你是 Agent 行为分析专家。'),
    LlmMessage('user', prompt),
  ]);
  return result.content;
}

/// 基于失败模式生成改进的 prompt 变体。
Future<PromptVariant> generateVariant({
  required LlmProvider llm,
  required SystemPrompt prompt,
  required String sectionName,
  required String failurePatterns,
  String? parentId,
}) async {
  final String current = sectionText(prompt, sectionName);
  final String generationPrompt = '''
当前 prompt section「$sectionName」：
$current

分析出的失败模式：
$failurePatterns

请生成一个改进的 prompt 变体，保持原有意图，但解决上述失败模式。
以 Markdown 格式返回改进后的 section 文本。
''';
  final LlmResult result = await llm.chat(<LlmMessage>[
    const LlmMessage('system', '你是 prompt 工程专家。'),
    LlmMessage('user', generationPrompt),
  ]);
  return PromptVariant(
    id: 'variant-${DateTime.now().microsecondsSinceEpoch}',
    sectionName: sectionName,
    text: result.content,
    reason: failurePatterns,
    parentId: parentId,
    createdAt: DateTime.now(),
  );
}

/// 取 [prompt] 中名为 [name] 的 section 当前文本；未注册抛 [StateError]。
String sectionText(SystemPrompt prompt, String name) {
  for (final AssembledSection section in prompt.assemble().sections) {
    if (section.name == name) return section.text;
  }
  throw StateError('prompt 段 "$name" 未注册');
}

/// 把一条事件压缩为单行摘要（类型 + 前 3 个负载字段）。
String _summarizeEvent(SessionEvent event) {
  final Object? data = event.data;
  if (data is! Map || data.isEmpty) return event.type;
  final String payload = data.entries
      .take(3)
      .map((MapEntry<Object?, Object?> entry) => '${entry.key}=${entry.value}')
      .join(', ');
  return '${event.type}($payload)';
}
