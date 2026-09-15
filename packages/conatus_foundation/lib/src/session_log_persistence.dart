/// session log 的持久化后端：复用 append-only 的 [SessionPersistence]。
///
/// 这是三种后端里唯一**追加写入 O(1)** 的实现（一会话一文件，逐行 append），
/// 因此长会话下没有写放大；`DatabaseSessionLog` 会整表重写，见其 dartdoc。
library;

import 'session_log.dart';
import 'session_persistence.dart';
import 'session_types.dart';

/// 把 [SessionPersistence] 当作多会话只追加日志来用的 [SessionLog]。
class PersistenceSessionLog implements SessionLog {
  /// 用给定的持久化端口构造。
  PersistenceSessionLog(this.persistence);

  /// 底层持久化端口。
  final SessionPersistence persistence;

  final Map<String, int> _forks = <String, int>{};
  final Map<String, int> _seqs = <String, int>{};

  @override
  Future<SessionEvent> append(SessionEvent event) async {
    final String sessionId = requireEventSessionId(event);
    final SessionEvent stamped = event.copyWith(
      sessionId: sessionId,
      seq: await _takeSeq(sessionId),
    );
    await persistence.append(sessionId, stamped);
    return stamped;
  }

  /// 分配该会话的下一个 seq（首次使用时从已落盘的事件数续接）。
  Future<int> _takeSeq(String sessionId) async {
    final int? cached = _seqs[sessionId];
    final int seq = cached ?? (await persistence.load(sessionId)).length;
    _seqs[sessionId] = seq + 1;
    return seq;
  }

  @override
  Stream<SessionEvent> read(
    String sessionId, {
    DateTime? from,
    DateTime? to,
  }) async* {
    for (final SessionEvent event in await persistence.load(sessionId)) {
      if (eventInWindow(event, from: from, to: to)) yield event;
    }
  }

  @override
  Future<String> fork(
    String sessionId,
    String fromEventId, {
    String? newId,
  }) async {
    final List<SessionEvent> prefix =
        eventPrefix(await persistence.load(sessionId), fromEventId);
    final String target = newId ?? nextForkId(sessionId, _forks);
    for (final SessionEvent event in restampPrefix(prefix, target)) {
      await persistence.append(target, event);
    }
    return target;
  }

  @override
  Future<void> replay(
    String sessionId,
    void Function(SessionEvent event) handler,
  ) async {
    for (final SessionEvent event in await persistence.load(sessionId)) {
      handler(event);
    }
  }

  @override
  Future<List<String>> list() => persistence.list();

  @override
  Future<void> close() async {}
}
