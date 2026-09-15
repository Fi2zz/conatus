/// session log 的 Database 后端：把事件存进 `Database` hub 的一个 unit。
///
/// 键为 `<sessionId 长度>:<sessionId>:<seq 补零 9 位>`，长度前缀保证不同会话
/// 之间不可能前缀冲突，补零保证字典序等于 seq 序。
///
/// **性能注意**：`DatabaseUnit.put` 每次都会把整个 unit 的表交给后端 `save`
/// （JSON 后端是整文件原子写），所以逐事件键在长会话下是 O(n²) 写放大。长期
/// 运行的会话建议用 `PersistenceSessionLog`（追加式）；本后端适合小会话与
/// 需要事务式整表快照的场景。
///
/// 本类**拥有**它解析到的 unit：`close()` 会关闭该 unit 句柄。
library;

import 'database.dart';
import 'database_unit.dart';
import 'session_log.dart';
import 'session_types.dart';

/// 把事件按会话存进 [Database] 某个 unit 的 [SessionLog]。
class DatabaseSessionLog implements SessionLog {
  /// 用给定的 [Database] 与 unit 名构造。
  DatabaseSessionLog(this.database, {this.unit = 'session_log'});

  /// 键值存储 hub。
  final Database database;

  /// 事件所在 unit 名。
  final String unit;

  final Map<String, int> _forks = <String, int>{};
  final Map<String, int> _seqs = <String, int>{};
  DatabaseUnit? _handle;

  @override
  Future<SessionEvent> append(SessionEvent event) async {
    final String sessionId = requireEventSessionId(event);
    final SessionEvent stamped =
        event.copyWith(sessionId: sessionId, seq: await _takeSeq(sessionId));
    final DatabaseUnit handle = await _resolveUnit();
    await handle.put(_key(sessionId, stamped.seq), stamped.toJson());
    return stamped;
  }

  /// 分配该会话的下一个 seq（首次使用时从已落盘的事件数续接）。
  Future<int> _takeSeq(String sessionId) async {
    final int? cached = _seqs[sessionId];
    final int seq = cached ?? (await _eventsOf(sessionId)).length;
    _seqs[sessionId] = seq + 1;
    return seq;
  }

  @override
  Stream<SessionEvent> read(
    String sessionId, {
    DateTime? from,
    DateTime? to,
  }) async* {
    final DatabaseUnit handle = await _resolveUnit();
    final List<String> keys = _keysOf(handle, sessionId);
    for (final String key in keys) {
      final SessionEvent event = _decode(handle.get(key));
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
      await _eventsOf(sessionId),
      fromEventId,
    );
    final String target = newId ?? nextForkId(sessionId, _forks);
    for (final SessionEvent event in restampPrefix(prefix, target)) {
      await append(event);
    }
    return target;
  }

  @override
  Future<void> replay(
    String sessionId,
    void Function(SessionEvent event) handler,
  ) async {
    await for (final SessionEvent event in read(sessionId)) {
      handler(event);
    }
  }

  @override
  Future<List<String>> list() async {
    final DatabaseUnit handle = await _resolveUnit();
    final Set<String> ids = <String>{};
    for (final String key in handle.keys) {
      final String? id = _sessionIdOf(key);
      if (id != null) ids.add(id);
    }
    return ids.toList()..sort();
  }

  @override
  Future<void> close() async {
    _handle?.close();
    _handle = null;
  }

  Future<DatabaseUnit> _resolveUnit() async =>
      _handle ??= database.get(unit) ?? await database.open(unit);

  Future<List<SessionEvent>> _eventsOf(String sessionId) async => <SessionEvent>[
        await for (final SessionEvent event in read(sessionId)) event,
      ];

  List<String> _keysOf(DatabaseUnit handle, String sessionId) {
    final String prefix = _keyPrefix(sessionId);
    return handle.keys
        .where((String key) => key.startsWith(prefix))
        .toList()
      ..sort();
  }

  SessionEvent _decode(Object? value) {
    if (value is! Map) {
      throw const SessionLogException(
        'malformed-record',
        'session log unit 中的记录不是 JSON 对象',
      );
    }
    return SessionEvent.fromJson(Map<String, Object?>.from(value));
  }

  String _key(String sessionId, int seq) =>
      '${_keyPrefix(sessionId)}${seq.toString().padLeft(9, '0')}';

  /// 键的会话前缀：长度前缀保证不同会话 id 之间不可能互相成为前缀。
  String _keyPrefix(String sessionId) => '${sessionId.length}:$sessionId:';

  /// 从键里还原会话 id；键不合法时返回 `null`。
  String? _sessionIdOf(String key) {
    final int split = key.indexOf(':');
    if (split <= 0) return null;
    final int? length = int.tryParse(key.substring(0, split));
    if (length == null || length <= 0) return null;
    final int start = split + 1;
    if (start + length > key.length) return null;
    return key.substring(start, start + length);
  }
}
