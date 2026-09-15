/// skill 的命名器：由「任务 + 工具序列」生成技能名与描述。
library;

import 'package:conatus_llm/conatus_llm.dart';
import 'skill.dart';

/// 把任意文本规范为合法工具名。
String skillNameFrom(String text) {
  final String sanitized =
      text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  final String trimmed = sanitized.replaceAll(RegExp(r'^_+|_+$'), '');
  return trimmed.isEmpty ? 'skill' : trimmed;
}

/// 确定性兜底命名：名字由工具序列拼出。
Future<SkillMeta> deterministicSkillNamer(
    String task, List<String> tools) async {
  return SkillMeta(
    name: skillNameFrom('skill_${tools.join('_')}'),
    description: '自动沉淀的技能：依次调用 ${tools.join('、')}。',
  );
}

/// 用 LLM 生成技能名与描述，解析失败时回退确定性命名。
SkillNamer llmSkillNamer(LlmProvider llm, {Map<String, dynamic>? options}) =>
    (String task, List<String> tools) async {
      final LlmResult result = await llm.chat(
        <LlmMessage>[
          LlmMessage(
            'user',
            '任务：$task\n成功用到的工具序列：${tools.join(' -> ')}\n'
                '请为这个可复用技能取一个 snake_case 英文名并写一句中文描述。'
                '只回 JSON：{"name":"...","description":"..."}',
          ),
        ],
        options: options,
      );
      return parseSkillMeta(result.content, tools);
    };

/// 从模型文本解析技能元信息，失败时回退确定性命名。
SkillMeta parseSkillMeta(String text, List<String> tools) {
  final RegExpMatch? nameMatch = RegExp(
    r'"name"\s*:\s*"([^"]+)"',
    caseSensitive: false,
  ).firstMatch(text);
  final RegExpMatch? descMatch = RegExp(
    r'"description"\s*:\s*"([^"]*)"',
    caseSensitive: false,
  ).firstMatch(text);
  if (nameMatch == null) {
    return SkillMeta(
      name: skillNameFrom('skill_${tools.join('_')}'),
      description: '自动沉淀的技能：依次调用 ${tools.join('、')}。',
    );
  }
  return SkillMeta(
    name: skillNameFrom(nameMatch.group(1)!),
    description: descMatch?.group(1) ?? '自动沉淀的技能：${tools.join('、')}。',
  );
}
