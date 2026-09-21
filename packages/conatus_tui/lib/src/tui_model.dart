/// 模型选择浮层状态：跨 provider 的模型列表 + 搜索 + provider 过滤。
///
/// 渲染与按键由根组件驱动（见 `tui.dart`）；本状态只管候选、过滤与选中。
library;

import 'package:nocterm/nocterm.dart';

/// 一个可选模型（含所属提供商）。
class TuiModelItem {
  const TuiModelItem({
    required this.provider,
    required this.model,
    this.current = false,
  });

  /// 所属提供商名。
  final String provider;

  /// 模型名。
  final String model;

  /// 是否为当前模型（渲染 `← 当前`）。
  final bool current;
}

/// 浮层同时可见的模型行数（超出滚动）。
const int kTuiModelVisible = 8;

/// 模型选择浮层状态。
class TuiModelPrompt {
  TuiModelPrompt({this.onChanged});

  /// 状态变化回调（组件据此重绘）。
  void Function()? onChanged;

  /// 搜索输入框（浮层打开时聚焦，`type to search`）。
  final TextEditingController search = TextEditingController();

  List<TuiModelItem> _all = const <TuiModelItem>[];
  String _query = '';
  String? _provider;
  int _index = 0;
  bool _open = false;

  /// 浮层是否可见。
  bool get open => _open;

  /// 当前搜索词。
  String get query => _query;

  /// 当前 provider 过滤；`null` 表示全部。
  String? get providerFilter => _provider;

  /// 全部提供商名（过滤标签行，按首次出现顺序）。
  List<String> get providers {
    final List<String> names = <String>[];
    for (final TuiModelItem item in _all) {
      if (!names.contains(item.provider)) {
        names.add(item.provider);
      }
    }
    return names;
  }

  /// 过滤后的候选（provider 过滤 + 搜索词）。
  List<TuiModelItem> get matches => <TuiModelItem>[
        for (final TuiModelItem item in _all)
          if ((_provider == null || item.provider == _provider) &&
              (_query.isEmpty || item.model.contains(_query)))
            item,
      ];

  /// 当前选中下标。
  int get index => _index;

  /// 当前选中项；无候选返回 `null`。
  TuiModelItem? get selected {
    final List<TuiModelItem> list = matches;
    if (list.isEmpty) {
      return null;
    }
    return list[_index < list.length ? _index : list.length - 1];
  }

  /// 可见窗口起点（选中项始终在窗口内）。
  int get windowStart {
    final int length = matches.length;
    if (length <= kTuiModelVisible) {
      return 0;
    }
    final int start = _index - kTuiModelVisible ~/ 2;
    if (start < 0) {
      return 0;
    }
    return start + kTuiModelVisible > length
        ? length - kTuiModelVisible
        : start;
  }

  /// 打开并载入候选（默认选中当前模型）。
  void show(List<TuiModelItem> items) {
    _all = items;
    _query = '';
    _provider = null;
    search.text = '';
    _index = items.indexWhere((TuiModelItem item) => item.current);
    if (_index < 0) {
      _index = 0;
    }
    _open = true;
    onChanged?.call();
  }

  /// 设置搜索词（搜索框变化时调用）。
  void setQuery(String text) {
    _query = text.trim();
    _clampIndex();
    onChanged?.call();
  }

  /// Tab：全部 → 各提供商 → 全部。
  void toggleProvider() {
    final List<String> names = providers;
    if (names.isEmpty) {
      return;
    }
    if (_provider == null) {
      _provider = names.first;
    } else {
      final int next = names.indexOf(_provider!) + 1;
      _provider = next >= names.length ? null : names[next];
    }
    _clampIndex();
    onChanged?.call();
  }

  /// 移动光标（越界钳制；无候选无操作）。
  void move(int delta) {
    final int length = matches.length;
    if (length == 0) {
      return;
    }
    final int next = _index + delta;
    _index = next < 0 ? 0 : (next >= length ? length - 1 : next);
    onChanged?.call();
  }

  /// 关闭面板。
  void close() {
    _open = false;
    _all = const <TuiModelItem>[];
    _query = '';
    _provider = null;
    _index = 0;
    search.text = '';
    onChanged?.call();
  }

  void _clampIndex() {
    final int length = matches.length;
    if (length == 0) {
      _index = 0;
    } else if (_index >= length) {
      _index = length - 1;
    }
  }
}
