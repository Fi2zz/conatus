/// 选项浮层视图：标题 + 按键提示 + 选项列表（选中项高亮，当前项带标记）。
///
/// 按键在根组件处理（见 `tui.dart`），本组件只渲染 [TuiChoiceRequest]。
library;

import 'package:nocterm/nocterm.dart';

import 'tui_choice.dart';

/// 选项浮层。
class TuiChoiceView extends StatelessComponent {
  const TuiChoiceView({
    super.key,
    required this.request,
    required this.selected,
  });

  /// 当前提问。
  final TuiChoiceRequest request;

  /// 当前选中下标。
  final int selected;

  @override
  Component build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(1),
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        border: BoxBorder.all(color: Colors.brightBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Component>[
          Text(
            request.title,
            style: const TextStyle(
              color: Colors.brightBlue,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            '↑↓ 选择 · Enter 确认 · Esc 取消',
            style: TextStyle(color: Colors.gray),
          ),
          const SizedBox(height: 1),
          for (int i = 0; i < request.choices.length; i++)
            _row(request.choices[i], i == selected),
        ],
      ),
    );
  }

  Component _row(TuiChoice choice, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      color: isSelected ? const Color.fromRGB(30, 40, 60) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Component>[
          Row(
            children: <Component>[
              Text(
                '${isSelected ? '>' : ' '} ${choice.label}',
                style: TextStyle(
                  color: isSelected ? Colors.brightWhite : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              if (choice.current) ...<Component>[
                const Text(' '),
                const Text(
                  '← 当前',
                  style: TextStyle(color: Colors.brightYellow),
                ),
              ],
            ],
          ),
          if (choice.description.isNotEmpty)
            Text(
              '  ${choice.description}',
              style: const TextStyle(color: Colors.gray),
            ),
        ],
      ),
    );
  }
}
