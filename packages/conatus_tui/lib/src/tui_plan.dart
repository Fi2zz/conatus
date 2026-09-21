/// Plan Mode 面板浮层状态：当前状态与计划，Enter 切换。
library;

import 'package:conatus_agent/conatus_agent.dart';

/// Plan Mode 面板浮层状态。
///
/// 面板是**展示 + 单动作**（Enter 进入/退出），不承载选择列表；按键在根组件
/// 处理（见 `tui.dart`）。
class TuiPlanPrompt {
  TuiPlanPrompt({this.onChanged});

  /// 状态变化回调（组件据此重绘）。
  void Function()? onChanged;

  bool _active = false;
  Plan? _plan;
  bool _open = false;

  /// 面板是否可见。
  bool get open => _open;

  /// Plan Mode 是否已激活。
  bool get active => _active;

  /// 当前计划；尚未写入为 `null`。
  Plan? get plan => _plan;

  /// 打开面板。
  void show({required bool active, Plan? plan}) {
    _active = active;
    _plan = plan;
    _open = true;
    onChanged?.call();
  }

  /// 刷新状态（切换后调用，保持面板打开）。
  void refresh({required bool active, Plan? plan}) {
    if (!_open) {
      return;
    }
    _active = active;
    _plan = plan;
    onChanged?.call();
  }

  /// 关闭面板。
  void close() {
    _open = false;
    _plan = null;
    onChanged?.call();
  }
}
