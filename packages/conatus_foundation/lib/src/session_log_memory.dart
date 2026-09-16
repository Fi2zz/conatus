/// session log 的内存后端：进程内的多会话事件日志。
///
/// 适合测试与短生命周期进程；进程退出即丢失。服务键 `'sessionLog'`，
/// 装配见 `session_log_provider.dart`。
library;

import 'session_log.dart';
import 'session_types.dart';

/// 把事件按会话存在内存里的 [SessionLog]。
class InMemorySessionLog implements SessionLog {
  final Map<String, List<SessionEvent>> _sessions =
      <String, List<SessionEvent>>{};
  final Map<String, int> _forks = <String, int>{};
  bool _closed = false;

  /// 是否已关闭。
  bool get closed => _closed;

  @override
  Future<SessionEvent> append(SessionEvent event) async {
    final String sessionId = requireEventSessionId(event);
    final List<SessionEvent> events =
        _sessions.putIfAbsent(sessionId, () => <SessionEvent>[]);
    final SessionEvent stamped =
        event.copyWith(sessionId: sessionId, seq: events.length);
    events.add(stamped);
    return stamped;
  }

  @override
  Stream<SessionEvent> read(
    String sessionId, {
    DateTime? from,
    DateTime? to,
  }) async* {
    for (final SessionEvent event
        in _sessions[sessionId] ?? const <SessionEvent>[]) {
      if (eventInWindow(event, from: from, to: to)) yield event;
    }
  }

  @override
  Future<String> fork(
    String sessionId,
    String fromEventId, {
    String? newId,
  }) async {
    final List<SessionEvent> prefix = eventPrefix(
      _sessions[sessionId] ?? const <SessionEvent>[],
      fromEventId,
    );
    final String target = newId ?? nextForkId(sessionId, _forks);
    _sessions[target] = restampPrefix(prefix, target);
    return target;
  }

  @override
  Future<void> replay(
    String sessionId,
    void Function(SessionEvent event) handler,
  ) async {
    for (final SessionEvent event in List<SessionEvent>.of(
        _sessions[sessionId] ?? const <SessionEvent>[])) {
      handler(event);
    }
  }

  @override
  Future<List<String>> list() async => _sessions.keys.toList()..sort();

  @override
  Future<void> close() async {
    _closed = true;
    _sessions.clear();
    _forks.clear();
  }
}
