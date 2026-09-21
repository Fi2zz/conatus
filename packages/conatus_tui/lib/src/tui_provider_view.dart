/// provider 管理浮层视图：标题 + 按键提示 + 提供商列表（名 / 端点 / 当前标记）。
///
/// 按键在根组件处理（见 `tui.dart`），本组件只渲染 [TuiProviderItem] 列表。
library;

import 'package:nocterm/nocterm.dart';

import 'tui_provider.dart';

/// provider 浮层。
class TuiProviderView extends StatelessComponent {
  const TuiProviderView({
    super.key,
    required this.items,
    required this.selected,
  });

  /// 列表项。
  final List<TuiProviderItem> items;

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
          const Text(
            'Providers',
            style: TextStyle(
              color: Colors.brightBlue,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            '↑↓ 选择 · Enter 切换 · D 删除 · Esc 取消',
            style: TextStyle(color: Colors.gray),
          ),
          const SizedBox(height: 1),
          for (int i = 0; i < items.length; i++)
            _row(items[i], i == selected),
        ],
      ),
    );
  }

  Component _row(TuiProviderItem item, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      color: isSelected ? const Color.fromRGB(30, 40, 60) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Component>[
          Row(
            children: <Component>[
              Text(
                '${isSelected ? '>' : ' '} ${item.label}',
                style: TextStyle(
                  color: isSelected ? Colors.brightWhite : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              if (item.current) ...<Component>[
                const Text(' '),
                const Text('← 当前', style: TextStyle(color: Colors.brightYellow)),
              ],
            ],
          ),
          if (item.baseUrl.isNotEmpty)
            Text(
              '    ${item.baseUrl}',
              style: const TextStyle(color: Colors.gray),
            ),
        ],
      ),
    );
  }
}
