/// 技能斜杠命令：把技能注册表投影成 `/skill:<技能名>` 命令，并负责展开与折叠。
///
/// 用户侧入口与模型侧 `skill` 工具共用同一份注册表与同一种正文块形态：调用时
/// 把 `<skill_content>` 块作为一轮用户输入交给 Agent Loop，因此正文照常进
/// `user/message` 事件，「模型可见即已记录」不变。
library;

import 'package:conatus_skill/conatus_skill.dart';

import 'tui_commands.dart';

/// 菜单里一条技能命令的说明长度上限（一行放得下）。
const int kTuiSkillDescriptionMaxLength = 60;

/// 技能命令前缀：`/skill:<技能名>`，与静态命令天然隔离。
const String kTuiSkillCommandPrefix = 'skill:';

/// 裸 `/skill` 的用法提示。
const String kTuiSkillUsage =
    '用法：/skill:<技能名> [补充要求]（/help 查看可用技能）。';

/// 技能正文块的起始标记。
const String _skillOpen = '<skill_content name="';

/// 技能正文块的结束标记。
const String _skillClose = '</skill_content>';

/// 把注册表里的技能投影成斜杠命令。
///
/// 用 [SkillRegistry.available] 而不是 `modelInvocable`：`disable-model-invocation`
/// 的技能对模型隐藏，但正是给用户手动触发的。命令统一带 `skill:` 前缀
/// （`/skill:<技能名>`），不与静态命令共享命名空间。
List<TuiCommand> skillTuiCommands(SkillRegistry? registry) {
  if (registry == null) return const <TuiCommand>[];
  final List<TuiCommand> commands = <TuiCommand>[];
  for (final SkillSummary summary in registry.available) {
    commands.add(TuiCommand(
      name: '$kTuiSkillCommandPrefix${summary.name}',
      description: normalizeSkillDescription(
        summary.description,
        maxLength: kTuiSkillDescriptionMaxLength,
      ),
    ));
  }
  return commands;
}

/// 把一次 `/<技能名> [补充要求]` 调用展开成交给模型的一轮用户输入。
String renderSkillPrompt(SkillDefinition definition, String arg) {
  final String block = renderSkillContent(definition);
  return arg.isEmpty ? block : '$block\n\n$arg';
}

/// [renderSkillPrompt] 的逆操作：把展开的正文块折叠回
/// `/skill:<技能名> <补充要求>`。
///
/// 屏上记录用折叠后的形态——正文块可能有几百行，但它必须原样进事件流。
/// 不是技能展开的文本原样返回。
String collapseSkillPrompt(String text) {
  if (!text.startsWith(_skillOpen)) return text;
  final int nameEnd = text.indexOf('"', _skillOpen.length);
  final int blockEnd = text.indexOf(_skillClose);
  if (nameEnd < 0 || blockEnd < nameEnd) return text;
  final String name = text.substring(_skillOpen.length, nameEnd);
  final String rest = text.substring(blockEnd + _skillClose.length).trim();
  return rest.isEmpty
      ? '/$kTuiSkillCommandPrefix$name'
      : '/$kTuiSkillCommandPrefix$name $rest';
}
