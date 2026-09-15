/// TUI 帮助文案：由命令表 [tuiCommands] 生成，与 `/` 菜单共用同一份数据。
library;

import 'tui_commands.dart';

/// 生成帮助文本。
String buildTuiHelpText() {
  final StringBuffer buffer = StringBuffer('命令（输入 / 弹出命令菜单）：\n');
  for (final TuiCommand command in tuiCommands) {
    buffer.writeln('  ${command.usage.padRight(16)}${command.description}');
  }
  buffer.writeln('其他输入直接进入 Agent 对话链路。');
  buffer.write('按键：Esc 关闭面板；Ctrl+C 连按两次退出。');
  return buffer.toString();
}

/// 帮助文案（构建一次）。
final String tuiHelpText = buildTuiHelpText();
