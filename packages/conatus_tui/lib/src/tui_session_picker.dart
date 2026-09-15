/// TUI 会话选择面板状态：汇合活跃与已持久化会话、移动光标、取选中 id。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

/// 会话面板中的一行。
class TuiSessionInfo {
  const TuiSessionInfo({
    required this.id,
    required this.active,
    required this.events,
    this.updatedAt,
  });

  /// 会话 id。
  final String id;

  /// 是否在内存中已打开。
  final bool active;

  /// 已记录的事件数（未打开时为 0）。
  final int events;

  /// 最近一次事件时间（未打开或空会话为 `null`）。
  final DateTime? updatedAt;
}

/// 会话选择面板状态。
class TuiSessionPicker {
  TuiSessionPicker(this._sessions, {required this.onChanged});

  final SessionStore _sessions;

  /// 状态变化回调。
  final void Function() onChanged;

  /// 面板是否打开。
  bool open = false;

  /// 会话列表。
  List<TuiSessionInfo> list = const <TuiSessionInfo>[];

  /// 当前光标。
  int index = 0;

  /// 打开面板：汇合活跃会话与已持久化会话，并定位到当前会话。
  Future<void> show(String currentId) async {
    final Set<String> ids = <String>{
      ..._sessions.ids,
      ...await _sessions.persistedIds(),
    };
    final List<TuiSessionInfo> infos = <TuiSessionInfo>[];
    for (final String id in ids) {
      final Session? session = _sessions.get(id);
      final List<SessionEvent> events =
          session?.events ?? const <SessionEvent>[];
      infos.add(TuiSessionInfo(
        id: id,
        active: session != null,
        events: events.length,
        updatedAt: events.isEmpty ? null : events.last.time,
      ));
    }
    infos.sort((TuiSessionInfo a, TuiSessionInfo b) => a.id.compareTo(b.id));
    list = infos;
    index = list.indexWhere((TuiSessionInfo info) => info.id == currentId);
    if (index < 0) {
      index = 0;
    }
    open = true;
    onChanged();
  }

  /// 关闭面板。
  void close() {
    open = false;
    onChanged();
  }

  /// 移动光标（越界钳制；空列表无操作）。
  void move(int delta) {
    if (list.isEmpty) {
      return;
    }
    final int next = index + delta;
    index = next < 0 ? 0 : (next >= list.length ? list.length - 1 : next);
    onChanged();
  }

  /// 当前选中会话 id；空列表返回 `null`。
  String? selectedId() => list.isEmpty ? null : list[index].id;
}
