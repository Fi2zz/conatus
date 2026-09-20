/// TUI 选项浮层状态：把「模型/审批要用户选一项」表达成一次异步提问。
///
/// 提问方 `await ask(request)` 拿到选中项 id（取消或超时得到 `null`）；
/// 渲染与按键由根组件驱动 [move] / [confirm] / [cancel]。工具与工具审批
/// 共用这一条通道，避免各自维护一套弹窗与超时。
library;

import 'dart:async';

/// 一个选项。
class TuiChoice {
  const TuiChoice({
    required this.id,
    required this.label,
    this.description = '',
    this.current = false,
  });

  /// 回传给提问方的标识。
  final String id;

  /// 选项名。
  final String label;

  /// 选项说明（灰字，可空）。
  final String description;

  /// 是否为当前取值（渲染 `← 当前` 标记）。
  final bool current;
}

/// 一次提问的内容。
class TuiChoiceRequest {
  const TuiChoiceRequest({required this.title, required this.choices});

  /// 标题行。
  final String title;

  /// 可选项。
  final List<TuiChoice> choices;
}

/// 选项浮层状态。
class TuiChoicePrompt {
  TuiChoicePrompt({this.onChanged});

  /// 状态变化回调（组件据此重绘）；控制器构造时接上。
  void Function()? onChanged;

  TuiChoiceRequest? _request;
  int _index = 0;
  Completer<String?>? _pending;

  /// 浮层是否可见。
  bool get open => _request != null;

  /// 当前提问；无提问为 `null`。
  TuiChoiceRequest? get request => _request;

  /// 当前选中项下标。
  int get index => _index;

  /// 发起一次提问，返回选中项 id；[cancel] 或超时返回 `null`。
  ///
  /// 超时由本方法统一管理（提问方不必再套一层 timeout，避免双重竞争）。
  /// 已有提问未收口时，旧提问先以 `null` 收口。
  Future<String?> ask(TuiChoiceRequest request, {Duration? timeout}) {
    cancel();
    _request = request;
    _index = request.choices.indexWhere((TuiChoice choice) => choice.current);
    if (_index < 0) {
      _index = 0;
    }
    final Completer<String?> completer = Completer<String?>();
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

  /// 移动光标（越界钳制；无提问无操作）。
  void move(int delta) {
    final TuiChoiceRequest? request = _request;
    if (request == null || request.choices.isEmpty) {
      return;
    }
    final int last = request.choices.length - 1;
    final int next = _index + delta;
    _index = next < 0 ? 0 : (next > last ? last : next);
    onChanged?.call();
  }

  /// 确认当前选中项。
  void confirm() {
    final TuiChoiceRequest? request = _request;
    final Completer<String?>? pending = _pending;
    if (request == null || pending == null || request.choices.isEmpty) {
      return;
    }
    _settle(pending, request.choices[_index].id);
  }

  /// 取消当前提问（幂等）。
  void cancel() {
    final Completer<String?>? pending = _pending;
    if (pending != null) {
      _settle(pending, null);
    }
  }

  /// 收口指定提问；若它已被后续提问取代则不动作。
  void _settle(Completer<String?> pending, String? result) {
    if (!identical(_pending, pending)) {
      return;
    }
    _pending = null;
    _request = null;
    if (!pending.isCompleted) {
      pending.complete(result);
    }
    onChanged?.call();
  }
}
