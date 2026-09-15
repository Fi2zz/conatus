/// `/` 命令菜单浮层：紧贴输入框上方，列出匹配命令与说明，高亮当前选中项。
library;

import 'package:nocterm/nocterm.dart';

import 'tui_commands.dart';

/// 命令菜单视图；按键与过滤在 [TuiCommandMenu] / 根组件处理。
class TuiCommandMenuView extends StatelessComponent {
  const TuiCommandMenuView({
    super.key,
    required this.matches,
    required this.selected,
  });

  /// 匹配到的命令。
  final List<TuiCommand> matches;

  /// 当前选中项下标。
  final int selected;

  @override
  Component build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: const Color.fromRGB(20, 20, 40),
        border: BoxBorder.all(color: Colors.brightBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Component>[
          for (int i = 0; i < matches.length; i++)
            _row(matches[i], i == selected),
        ],
      ),
    );
  }

  Component _row(TuiCommand command, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      color: isSelected ? const Color.fromRGB(30, 40, 60) : null,
      child: Row(
        children: <Component>[
          SizedBox(
            width: 14,
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
