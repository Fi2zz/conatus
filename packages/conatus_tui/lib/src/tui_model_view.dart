/// 模型选择浮层视图：搜索框 + provider 过滤标签 + 模型列表（滚动窗口）。
///
/// 按键在根组件处理（见 `tui.dart`），本组件只渲染 [TuiModelPrompt]。
library;

import 'package:nocterm/nocterm.dart';

import 'tui_model.dart';

/// 模型选择浮层。
class TuiModelView extends StatelessComponent {
  const TuiModelView({
    super.key,
    required this.prompt,
    this.onKeyEvent,
  });

  /// 浮层状态。
  final TuiModelPrompt prompt;

  /// 搜索框按键拦截（Tab / ↑↓ / Enter / Esc；其余交给输入框）。
  final bool Function(KeyboardEvent event)? onKeyEvent;

  @override
  Component build(BuildContext context) {
    final List<TuiModelItem> matches = prompt.matches;
    final int start = prompt.windowStart;
    final int end = start + kTuiModelVisible > matches.length
        ? matches.length
        : start + kTuiModelVisible;
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
            'Select a model',
            style: TextStyle(
              color: Colors.brightBlue,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            'Tab 切换提供商 · ↑↓ 选择 · Enter 确认 · Esc 取消',
            style: TextStyle(color: Colors.gray),
          ),
          _providerTabs(),
          _search(),
          const SizedBox(height: 1),
          if (matches.isEmpty)
            const Text('（无匹配模型）', style: TextStyle(color: Colors.gray))
          else
            for (int i = start; i < end; i++)
              _row(matches[i], i == prompt.index),
          if (end < matches.length)
            Text(
              '▼ 还有 ${matches.length - end} 个',
              style: const TextStyle(color: Colors.gray),
            ),
        ],
      ),
    );
  }

  /// provider 过滤标签行：`[All]` 与各提供商，当前过滤高亮。
  Component _providerTabs() {
    return Row(
      children: <Component>[
        _tab('All', prompt.providerFilter == null),
        for (final String name in prompt.providers) _tab(name, prompt.providerFilter == name),
      ],
    );
  }

  Component _tab(String label, bool active) => Text(
        active ? '[$label] ' : '$label  ',
        style: TextStyle(
          color: active ? Colors.brightYellow : Colors.gray,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
        ),
      );

  Component _search() {
    return Row(
      children: <Component>[
        const Text('> ', style: TextStyle(color: Colors.green)),
        Expanded(
          child: TextField(
            // 稳定 key：搜索触发重建时保持元素身份，否则焦点丢失。
            key: const ValueKey<String>('model-search'),
            controller: prompt.search,
            focused: true,
            placeholder: '输入过滤模型名',
            style: const TextStyle(color: Colors.white),
            onKeyEvent: onKeyEvent,
            onChanged: prompt.setQuery,
          ),
        ),
      ],
    );
  }

  Component _row(TuiModelItem item, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      color: isSelected ? const Color.fromRGB(30, 40, 60) : null,
      child: Row(
        children: <Component>[
          SizedBox(
            width: 30,
            child: Text(
              '${isSelected ? '>' : ' '} ${item.model}',
              style: TextStyle(
                color: isSelected ? Colors.brightWhite : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          const Text('  '),
          Expanded(
            child: Text(
              item.provider,
              style: TextStyle(color: isSelected ? Colors.white : Colors.gray),
            ),
          ),
          if (item.current)
            const Text('← 当前', style: TextStyle(color: Colors.brightYellow)),
        ],
      ),
    );
  }
}
