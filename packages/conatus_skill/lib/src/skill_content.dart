/// 技能正文块的渲染：`skill` 工具的结果与将来的直接调用共用同一种形态。
library;

import 'skill_types.dart';

/// 渲染一段技能正文块（`<skill_content>`），模型据此执行指令。
String renderSkillContent(SkillDefinition definition) {
  final SkillSummary summary = definition.summary;
  final StringBuffer buffer = StringBuffer()
    ..write('<skill_content name="')
    ..write(escapeSkillAttribute(summary.name))
    ..write('">\n<skill_resources>\n')
    ..write(renderSkillResourceHint(definition.resourceBase, summary.provider))
    ..write('\n</skill_resources>\n\n<skill_instructions>\n')
    ..write(definition.content)
    ..write('\n</skill_instructions>\n</skill_content>');
  return buffer.toString();
}

/// 资源基址提示；未声明基址时指向 provider。
String renderSkillResourceHint(SkillResourceBase? base, String provider) {
  const String tail = 'Load referenced resources only as needed.';
  switch (base) {
    case null:
      return 'Resources for this skill are managed by provider "$provider". '
          '$tail';
    case SkillDirectoryResource(:final String path):
      return 'Base directory for this skill: $path\n'
          'Resolve relative paths mentioned by this skill against the base '
          'directory before using them. $tail';
    case SkillUrlResource(:final String url):
      return 'Base URL for this skill: $url\n'
          'Resolve relative URLs mentioned by this skill against the base URL '
          'before using them. $tail';
    case SkillOpaqueResource(:final String description):
      return 'Resources for this skill: $description\n$tail';
  }
}

/// 转义出现在属性值里的文本（`&`、`"`、`<`）。
String escapeSkillAttribute(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;');
