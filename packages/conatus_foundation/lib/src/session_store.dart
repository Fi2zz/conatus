/// session-store 插件：多会话的创建、打开、关闭与持久化接线。
///
/// 服务键 `'sessions'`。打开一个会话时从 [SessionPersistence] 载入既有事件
/// 作为种子（不会重复落盘），之后每次追加都异步写入；[SessionStore.flush]
/// 等待所有在途写入落定。
library;

import 'package:conatus_core/conatus_core.dart';
import 'session.dart';
import 'session_persistence.dart';
import 'session_types.dart';

/// 会话仓库：进程内持有活跃会话，并可选地持久化其事件。
class SessionStore {
  SessionStore({SessionPersistence? persistence}) : _persistence = persistence;

  final SessionPersistence? _persistence;
  final Map<String, Session> _sessions = <String, Session>{};
  final List<Future<void>> _writes = <Future<void>>[];
  int _seq = 0;

  /// 活跃会话 id。
  List<String> get ids => _sessions.keys.toList(growable: false);

  /// 活跃会话数。
  int get length => _sessions.length;

  /// 查找活跃会话；未打开返回 `null`。
  Session? get(String id) => _sessions[id];

  /// 创建新会话；[id] 缺省时自动生成。同 id 重复创建抛 [StateError]。
  Session create({String? id}) {
    final String resolved = id ?? _nextId();
    if (_sessions.containsKey(resolved)) {
      throw StateError('会话 "$resolved" 已存在');
    }
    final Session session = Session(id: resolved);
    _attach(session);
    _sessions[resolved] = session;
    return session;
  }

  /// 打开会话：已活跃则直接返回，否则从持久化载入事件作为种子。
  Future<Session> open(String id) async {
    final Session? active = _sessions[id];
    if (active != null) return active;
    final SessionPersistence? persistence = _persistence;
    final List<SessionEvent> seed = persistence == null
        ? const <SessionEvent>[]
        : await persistence.load(id);
    final Session session = Session(id: id, seed: seed);
    _attach(session);
    _sessions[id] = session;
    return session;
  }

  /// 关闭并移除活跃会话。返回是否确实移除了一个。
  bool close(String id) {
    final Session? session = _sessions.remove(id);
    if (session == null) return false;
    session.close();
    return true;
  }

  /// 关闭并删除某会话的持久化数据。返回是否有东西被处理。
  Future<bool> remove(String id) async {
    final bool closed = close(id);
    final SessionPersistence? persistence = _persistence;
    if (persistence != null) await persistence.remove(id);
    return closed || persistence != null;
  }

  /// 已持久化的会话 id（未接持久化时为空）。
  Future<List<String>> persistedIds() async {
    final SessionPersistence? persistence = _persistence;
    if (persistence == null) return const <String>[];
    return persistence.list();
  }

  /// 等待所有在途的持久化写入落定。
  Future<void> flush() async {
    final List<Future<void>> writes = List<Future<void>>.of(_writes);
    _writes.clear();
    await Future.wait(writes);
  }

  void _attach(Session session) {
    final SessionPersistence? persistence = _persistence;
    if (persistence != null) {
      session.onEvent((SessionEvent event) {
        _writes.add(persistence.append(session.id, event));
      });
    }
    session.onClose(() => _sessions.remove(session.id));
  }

  String _nextId() {
    _seq++;
    return 'session-${DateTime.now().microsecondsSinceEpoch}-$_seq';
  }
}

/// 将 [SessionStore] 作为 `'sessions'` 服务提供到上下文。
///
/// 未显式传入 [persistence] 时，复用上下文里已提供的 `'sessionPersistence'`。
SessionStore provideSessions(
  Context ctx, {
  SessionStore? sessions,
  SessionPersistence? persistence,
}) {
  final SessionPersistence? resolved =
      persistence ?? ctx.get<SessionPersistence>('sessionPersistence');
  final SessionStore store = sessions ?? SessionStore(persistence: resolved);
  ctx.provide('sessions', store);
  return store;
}
