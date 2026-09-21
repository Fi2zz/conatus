/// `/` 命令菜单浮层：紧贴输入框上方，限行滚动显示匹配命令与说明。
///
/// 按键与过滤在 [TuiCommandMenu] / 根组件处理。
library;

import 'package:nocterm/nocterm.dart';

import 'tui_commands.dart';

/// 命令菜单视图。
class TuiCommandMenuView extends StatelessComponent {
  const TuiCommandMenuView({
    super.key,
    required this.matches,
    required this.selected,
    this.windowStart = 0,
  });

  /// 匹配到的命令。
  final List<TuiCommand> matches;

  /// 当前选中项下标。
  final int selected;

  /// 可见窗口起点（超出部分滚动显示）。
  final int windowStart;

  @override
  Component build(BuildContext context) {
    final int end = windowStart + kTuiCommandMenuVisible > matches.length
        ? matches.length
        : windowStart + kTuiCommandMenuVisible;
    final int nameWidth = _nameWidth();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: const Color.fromRGB(20, 20, 40),
        border: BoxBorder.all(color: Colors.brightBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Component>[
          for (int i = windowStart; i < end; i++)
            _row(matches[i], i == selected, nameWidth),
          Text(
            '(${selected + 1}/${matches.length})',
            style: const TextStyle(color: Colors.gray),
          ),
        ],
      ),
    );
  }

  /// 命令名列宽：取最长命令词，钳制在 14—30 之间（过长名字不折行）。
  int _nameWidth() {
    int width = 14;
    for (final TuiCommand command in matches) {
      if (command.usage.length > width) {
        width = command.usage.length;
      }
    }
    return width > 30 ? 30 : width;
  }

  Component _row(TuiCommand command, bool isSelected, int nameWidth) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      color: isSelected ? const Color.fromRGB(30, 40, 60) : null,
      child: Row(
        children: <Component>[
          SizedBox(
            width: nameWidth.toDouble(),
            child: Text(
              command.usage,
              style: TextStyle(
                color: isSelected ? Colors.brightWhite : Colors.brightCyan,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          const Text('  '),
          Expanded(
            child: Text(
              command.description,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.gray,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
