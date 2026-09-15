/// session 插件：append-only 的会话事件日志。
///
/// 一条会话是一串不可修改的 [SessionEvent]（seq 从 0 单调递增）。追加会同步
/// 通知 [onEvent] 监听器（SessionStore 借此落盘），关闭会通知 [onClose] 并
/// 拒绝后续追加。多会话的创建与持久化见 `session_store.dart`。
library;

import 'package:conatus_core/conatus_core.dart';
import 'session_types.dart';

/// 一次会话：持有事件日志与监听器。
class Session {
  Session({
    required this.id,
    Iterable<SessionEvent> seed = const <SessionEvent>[],
  }) {
    _events.addAll(seed);
    _seq = _events.isEmpty ? 0 : _events.last.seq + 1;
    createdAt = _events.isEmpty ? DateTime.now() : _events.first.time;
  }

  /// 会话标识（也是持久化文件名）。
  final String id;

  /// 会话创建时间（取首条事件时间）。
  late final DateTime createdAt;

  final List<SessionEvent> _events = <SessionEvent>[];
  final List<void Function(SessionEvent)> _eventListeners =
      <void Function(SessionEvent)>[];
  final List<void Function()> _closeListeners = <void Function()>[];
  int _seq = 0;
  bool _closed = false;

  /// 事件日志的只读视图。
  List<SessionEvent> get events => List<SessionEvent>.unmodifiable(_events);

  /// 事件条数。
  int get length => _events.length;

  /// 是否已关闭。
  bool get closed => _closed;

  /// 追加一条事件并返回它。会话关闭后抛 [StateError]。
  SessionEvent append(String type, {Object? data}) {
    if (_closed) throw StateError('会话 "$id" 已关闭，无法追加事件');
    final SessionEvent event = SessionEvent(
      seq: _seq++,
      type: type,
      time: DateTime.now(),
      data: data,
    );
    _events.add(event);
    for (final void Function(SessionEvent) listener
        in List<void Function(SessionEvent)>.of(_eventListeners)) {
      listener(event);
    }
    return event;
  }

  /// 监听后续追加。返回撤销函数（幂等）。
  Disposer onEvent(void Function(SessionEvent event) listener) {
    _eventListeners.add(listener);
    return () => _eventListeners.remove(listener);
  }

  /// 监听会话关闭；已关闭时立即回调。返回撤销函数（幂等）。
  Disposer onClose(void Function() listener) {
    if (_closed) {
      listener();
      return () {};
    }
    _closeListeners.add(listener);
    return () => _closeListeners.remove(listener);
  }

  /// 关闭会话：通知关闭监听器并拒绝后续追加。幂等。
  void close() {
    if (_closed) return;
    _closed = true;
    final List<void Function()> listeners =
        List<void Function()>.of(_closeListeners);
    _closeListeners.clear();
    _eventListeners.clear();
    for (final void Function() listener in listeners) {
      listener();
    }
  }

  @override
  String toString() => 'Session($id, $length events)';
}
