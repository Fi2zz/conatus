/// `@` 文件补全浮层：紧贴输入框上方，列出候选路径与名字，末尾给出计数。
library;

import 'package:nocterm/nocterm.dart';

import 'at_ref_menu.dart';

/// 文件补全视图；按键与过滤在 [AtRefMenu] / 根组件处理。
class AtRefMenuView extends StatelessComponent {
  const AtRefMenuView({
    super.key,
    required this.matches,
    required this.selected,
  });

  /// 匹配到的候选。
  final List<AtRefCandidate> matches;

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
          Text(
            '(${selected + 1}/${matches.length})',
            style: const TextStyle(color: Colors.gray),
          ),
        ],
      ),
    );
  }

  Component _row(AtRefCandidate candidate, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      color: isSelected ? const Color.fromRGB(30, 40, 60) : null,
      child: Row(
        children: <Component>[
          SizedBox(
            width: 32,
            child: Text(
              candidate.path,
              style: TextStyle(
                color: isSelected ? Colors.brightWhite : Colors.brightCyan,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          const Text('  '),
          Expanded(
            child: Text(
              candidate.name,
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
