/// 通用多字段表单浮层状态：字段输入 + 焦点切换 + 提交 / 取消。
///
/// 渲染与按键由根组件驱动 [move] / [next] / [cancel]；[ask] 返回提交值
/// （`{字段名: 文本}`），取消或超时返回 `null`。控制器随请求一次性使用，
/// 收口后不再复用。
library;

import 'dart:async';

import 'package:nocterm/nocterm.dart';

/// 一个表单字段。
class TuiFormField {
  TuiFormField({required this.label, this.placeholder = '', this.obscure = false});

  /// 字段名（也是提交值的键）。
  final String label;

  /// 占位文案。
  final String placeholder;

  /// 是否掩码显示（令牌类字段）。
  final bool obscure;

  /// 文本控制器。
  final TextEditingController controller = TextEditingController();
}

/// 一次表单请求。
class TuiFormRequest {
  TuiFormRequest({
    required this.title,
    required this.hint,
    required this.fields,
  });

  /// 标题行。
  final String title;

  /// 说明行（灰字）。
  final String hint;

  /// 字段（至少一个）。
  final List<TuiFormField> fields;
}

/// 表单浮层状态。
class TuiFormPrompt {
  TuiFormPrompt({this.onChanged});

  /// 状态变化回调（组件据此重绘）。
  void Function()? onChanged;

  TuiFormRequest? _request;
  int _index = 0;
  Completer<Map<String, String>?>? _pending;

  /// 浮层是否可见。
  bool get open => _request != null;

  /// 当前请求；未打开为 `null`。
  TuiFormRequest? get request => _request;

  /// 当前字段下标。
  int get index => _index;

  /// 发起一次表单；提交返回字段值，取消 / 超时返回 `null`。
  ///
  /// 已有未收口的表单先以 `null` 收口。
  Future<Map<String, String>?> ask(TuiFormRequest request, {Duration? timeout}) {
    cancel();
    _request = request;
    _index = 0;
    final Completer<Map<String, String>?> completer =
        Completer<Map<String, String>?>();
    _pending = completer;
    onChanged?.call();
    if (timeout == null) {
      return completer.future;
    }
    return completer.future.timeout(timeout, onTimeout: () {
      _settle(completer, null);
      return null;
    });
  }

  /// 切换字段（越界钳制；未打开无操作）。
  void move(int delta) {
    final TuiFormRequest? request = _request;
    if (request == null || request.fields.isEmpty) {
      return;
    }
    final int last = request.fields.length - 1;
    final int next = _index + delta;
    _index = next < 0 ? 0 : (next > last ? last : next);
    onChanged?.call();
  }

  /// Enter：还有后续字段则聚焦下一个，否则提交。
  void next() {
    final TuiFormRequest? request = _request;
    if (request == null) {
      return;
    }
    if (_index < request.fields.length - 1) {
      move(1);
      return;
    }
    submit();
  }

  /// 提交当前字段值。
  void submit() {
    final TuiFormRequest? request = _request;
    final Completer<Map<String, String>?>? pending = _pending;
    if (request == null || pending == null) {
      return;
    }
    _settle(pending, <String, String>{
      for (final TuiFormField field in request.fields)
        field.label: field.controller.text.trim(),
    });
  }

  /// 取消当前表单（幂等）。
  void cancel() {
    final Completer<Map<String, String>?>? pending = _pending;
    if (pending == null) {
      return;
    }
    _settle(pending, null);
  }

  void _settle(
    Completer<Map<String, String>?> completer,
    Map<String, String>? value,
  ) {
    _request = null;
    _pending = null;
    _index = 0;
    if (!completer.isCompleted) {
      completer.complete(value);
    }
    onChanged?.call();
  }
}
