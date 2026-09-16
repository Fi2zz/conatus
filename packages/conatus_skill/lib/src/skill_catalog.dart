/// 技能目录的渲染：把可用技能压成一段注入 system prompt 的清单。
library;

import 'skill_types.dart';

/// 目录的引导句。
const String kSkillCatalogIntro =
    'A skill is a reusable set of task-specific instructions. '
    'The following skills are available in this session:';

/// 目录的收尾指令（本版只做模型侧调用，故不涉及用户直接调用）。
const String kSkillCatalogInstruction =
    'If the user names a skill, or the task clearly matches a skill\'s '
    'description, call the `skill` tool with the exact skill name before '
    'taking task actions. Load all applicable skills, then follow their full '
    'instructions. This catalog contains summaries only; do not infer or '
    'follow a skill\'s instructions until it has been loaded.';

/// description 在目录里的默认长度上限。
const int kSkillCatalogDescriptionMaxLength = 500;

/// 渲染技能目录；[skills] 必须非空（空目录不产生任何段）。
String renderSkillCatalog(
  List<SkillSummary> skills, {
  int descriptionMaxLength = kSkillCatalogDescriptionMaxLength,
}) {
  final StringBuffer buffer = StringBuffer()
    ..write('<system-reminder>\n')
    ..write(kSkillCatalogIntro)
    ..write('\n\n<available_skills>\n');
  for (final SkillSummary skill in skills) {
    buffer
      ..write('- `')
      ..write(skill.name)
      ..write('`: ')
      ..write(escapeSkillText(normalizeSkillDescription(
        skill.description,
        maxLength: descriptionMaxLength,
      )))
      ..write('\n');
  }
  buffer
    ..write('</available_skills>\n\n')
    ..write(kSkillCatalogInstruction)
    ..write('\n</system-reminder>');
  return buffer.toString();
}

/// 折叠空白并截断到 [maxLength]（截断时以 `...` 结尾）。
String normalizeSkillDescription(String description, {required int maxLength}) {
  final String collapsed = description.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.length <= maxLength) return collapsed;
  return '${collapsed.substring(0, maxLength - 3)}...';
}

/// 转义目录里的文本内容（`&`、`<`、`>`）。
String escapeSkillText(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
