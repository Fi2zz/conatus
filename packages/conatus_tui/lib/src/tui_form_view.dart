/// 表单浮层视图：标题 + 说明 + 字段输入 + 按键提示。
///
/// 按键在根组件处理（见 `tui.dart`），本组件只渲染 [TuiFormRequest]。
library;

import 'package:nocterm/nocterm.dart';

import 'tui_form.dart';

/// 表单浮层。
class TuiFormView extends StatelessComponent {
  const TuiFormView({
    super.key,
    required this.request,
    required this.index,
    this.onKeyEvent,
  });

  /// 当前表单。
  final TuiFormRequest request;

  /// 当前字段下标。
  final int index;

  /// 字段按键拦截（返回 true 吞掉）：Tab / ↑↓ 切字段、Enter 提交、Esc 取消。
  final bool Function(KeyboardEvent event)? onKeyEvent;

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
          Text(request.hint, style: const TextStyle(color: Colors.gray)),
          const SizedBox(height: 1),
          for (int i = 0; i < request.fields.length; i++)
            _field(request.fields[i], i == index),
          const SizedBox(height: 1),
          const Text(
            'Tab / ↑↓ 切换 · Enter 下一字段 · Esc 取消',
            style: TextStyle(color: Colors.gray),
          ),
        ],
      ),
    );
  }

  Component _field(TuiFormField field, bool isFocused) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Component>[
        Text(
          field.label,
          style: TextStyle(color: isFocused ? Colors.brightCyan : Colors.gray),
        ),
        Row(
          children: <Component>[
            const Text('> ', style: TextStyle(color: Colors.green)),
            Expanded(
              child: TextField(
                controller: field.controller,
                focused: isFocused,
                obscureText: field.obscure,
                placeholder: field.placeholder,
                style: const TextStyle(color: Colors.white),
                onKeyEvent: onKeyEvent,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
