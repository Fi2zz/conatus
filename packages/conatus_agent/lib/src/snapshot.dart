/// persistence 的类型与存储：会话快照 + 可插拔 [SnapshotStore]。
///
/// 快照带 schema 版本号；默认 [DatabaseSnapshotStore] 走 `Database`（JSON 后端），
/// 另有内存实现供测试。恢复与装配见 `recovery.dart`。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

/// 当前快照 schema 版本。
const int kSnapshotVersion = 1;

/// 快照相关错误。
class RecoveryException implements Exception {
  const RecoveryException(this.code, this.message);

  /// 机器可读错误码（`not-found` / `unsupported-version`）。
  final String code;

  /// 人可读说明。
  final String message;

  @override
  String toString() => 'RecoveryException($code): $message';
}

/// 一次会话快照：事件日志 + 版本 + 时间。
///
/// 计划以 `plan/updated` 事件存在，故一并被快照；长期记忆由 [MemoryStore] 自己的
/// 后端持久化。
class SessionSnapshot {
  const SessionSnapshot({
    required this.sessionId,
    required this.events,
    this.savedAt,
    this.version = kSnapshotVersion,
  });

  /// 从 JSON 反序列化；版本不符抛 [RecoveryException]。
  factory SessionSnapshot.fromJson(Map<String, Object?> json) {
    final int version = json['version'] as int? ?? 0;
    if (version != kSnapshotVersion) {
      throw RecoveryException(
        'unsupported-version',
        '快照版本 $version 不受支持（当前 $kSnapshotVersion）',
      );
    }
    return SessionSnapshot(
      sessionId: '${json['sessionId'] ?? ''}',
      events: <SessionEvent>[
        for (final Object? item
            in (json['events'] as List<Object?>?) ?? const <Object?>[])
          if (item is Map)
            SessionEvent.fromJson(Map<String, Object?>.from(item)),
      ],
      savedAt: DateTime.tryParse('${json['savedAt'] ?? ''}'),
    );
  }

  /// 会话 id。
  final String sessionId;

  /// 全部事件。
  final List<SessionEvent> events;

  /// 快照时间。
  final DateTime? savedAt;

  /// schema 版本。
  final int version;

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'version': version,
        'sessionId': sessionId,
        if (savedAt != null) 'savedAt': savedAt!.toIso8601String(),
        'events': <Map<String, Object?>>[
          for (final SessionEvent event in events) event.toJson(),
        ],
      };
}

/// 快照存储端口。
abstract class SnapshotStore {
  /// 保存（覆盖）一份快照。
  Future<void> save(SessionSnapshot snapshot);

  /// 载入快照；不存在返回 `null`。
  Future<SessionSnapshot?> load(String sessionId);

  /// 已保存的会话 id。
  Future<List<String>> list();

  /// 删除快照。
  Future<void> delete(String sessionId);
}

/// 内存实现（测试用）。
class MemorySnapshotStore implements SnapshotStore {
  final Map<String, SessionSnapshot> _snapshots = <String, SessionSnapshot>{};

  @override
  Future<void> save(SessionSnapshot snapshot) async {
    _snapshots[snapshot.sessionId] = snapshot;
  }

  @override
  Future<SessionSnapshot?> load(String sessionId) async =>
      _snapshots[sessionId];

  @override
  Future<List<String>> list() async => _snapshots.keys.toList(growable: false);

  @override
  Future<void> delete(String sessionId) async {
    _snapshots.remove(sessionId);
  }
}

/// `Database` 后端实现：一会话一条记录（键为会话 id）。
class DatabaseSnapshotStore implements SnapshotStore {
  DatabaseSnapshotStore(this.database, {this.unit = 'session_snapshots'});

  /// 存储 hub。
  final Database database;

  /// 存放快照的单元名。
  final String unit;

  Future<DatabaseUnit> _unit() async =>
      database.get(unit) ?? await database.open(unit);

  @override
  Future<void> save(SessionSnapshot snapshot) async {
    final DatabaseUnit store = await _unit();
    await store.put(snapshot.sessionId, snapshot.toJson());
  }

  @override
  Future<SessionSnapshot?> load(String sessionId) async {
    final Object? value = (await _unit()).get(sessionId);
    if (value is! Map) return null;
    return SessionSnapshot.fromJson(Map<String, Object?>.from(value));
  }

  @override
  Future<List<String>> list() async => (await _unit()).keys;

  @override
  Future<void> delete(String sessionId) async {
    await (await _unit()).delete(sessionId);
  }
}
