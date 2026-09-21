/// provider 管理浮层状态：列表选择 / 删除 / 新增入口。
///
/// 只持有屏上状态；注册表读写与切换动作在控制器（见 `tui_controller.dart`）。
library;

/// 列表里的一项。
class TuiProviderItem {
  const TuiProviderItem({
    required this.name,
    required this.baseUrl,
    required this.current,
    this.isAdd = false,
  });

  /// 提供商名；[isAdd] 为 true 时是「[ Add New Platform ]」占位项。
  final String name;

  /// 端点地址（列表第二行灰字）。
  final String baseUrl;

  /// 是否为当前选中的提供商（渲染 `← 当前`）。
  final bool current;

  /// 是否为新增入口项。
  final bool isAdd;

  /// 列表展示名。
  String get label => isAdd ? '[ Add New Platform ]' : name;
}

/// provider 浮层状态。
class TuiProviderPrompt {
  TuiProviderPrompt({this.onChanged});

  /// 状态变化回调（组件据此重绘）。
  void Function()? onChanged;

  List<TuiProviderItem> _items = const <TuiProviderItem>[];
  int _index = 0;
  bool _open = false;

  /// 浮层是否可见。
  bool get open => _open;

  /// 列表项。
  List<TuiProviderItem> get items => _items;

  /// 当前选中下标。
  int get index => _index;

  /// 当前选中项；无列表返回 `null`。
  TuiProviderItem? get selected => _items.isEmpty ? null : _items[_index];

  /// 打开并载入列表（默认选中当前提供商）。
  void show(List<TuiProviderItem> items) {
    _items = items;
    _open = true;
    final int current =
        items.indexWhere((TuiProviderItem item) => item.current);
    _index = current < 0 ? 0 : current;
    onChanged?.call();
  }

  /// 刷新列表（删除后保持下标有效）。
  void refresh(List<TuiProviderItem> items) {
    if (!_open) {
      return;
    }
    _items = items;
    if (_index >= items.length) {
      _index = items.isEmpty ? 0 : items.length - 1;
    }
    onChanged?.call();
  }

  /// 移动光标（越界钳制；空列表无操作）。
  void move(int delta) {
    if (_items.isEmpty) {
      return;
    }
    final int last = _items.length - 1;
    final int next = _index + delta;
    _index = next < 0 ? 0 : (next > last ? last : next);
    onChanged?.call();
  }

  /// 关闭面板。
  void close() {
    _open = false;
    _items = const <TuiProviderItem>[];
    _index = 0;
    onChanged?.call();
  }
}
