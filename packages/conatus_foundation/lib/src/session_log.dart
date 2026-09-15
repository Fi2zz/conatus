/// session log 插件：多会话的只追加事件日志抽象。
///
/// `Session` 是**单会话**的内存事件日志；[SessionLog] 面向**多会话**，按
/// `sessionId` 归档事件、按时间窗读取、从任意事件点分叉历史，并支持重放。
/// 只追加是硬不变式：日志永不改写，派生（[SessionLog.fork]）只产生新会话，
/// 源会话不受影响。
///
/// 具体后端见 `session_log_memory.dart`（进程内）、
/// `session_log_persistence.dart`（JSONL，追加式，推荐）与
/// `session_log_database.dart`（`Database` hub）；装配见
/// `session_log_provider.dart`。
library;

import 'session_types.dart';

/// 事件日志操作失败。
class SessionLogException implements Exception {
  /// 用错误码与说明构造。
  const SessionLogException(this.code, this.message);

  /// 机器可读的错误码。
  final String code;

  /// 人类可读的说明。
  final String message;

  @override
  String toString() => 'SessionLogException($code): $message';
}

/// 多会话的只追加事件日志。
abstract class SessionLog {
  /// 追加一条事件，返回落定后的事件。
  ///
  /// [SessionEvent.seq] 由日志按会话分配（每个会话从 0 起密集递增，等于该会话
  /// 在日志中的追加序号），入参自带的 seq 会被覆盖；[SessionEvent.id] 原样保留。
  /// 事件必须带非空 `sessionId`，否则抛 [ArgumentError]。
  Future<SessionEvent> append(SessionEvent event);

  /// 按 seq 顺序读取某会话的事件；[from] / [to] 为闭区间的时间过滤。
  Stream<SessionEvent> read(String sessionId, {DateTime? from, DateTime? to});

  /// 从 [fromEventId]（含）分叉出新会话，返回新会话 id。
  ///
  /// 源会话不受影响；[fromEventId] 不存在时抛 [StateError]。
  Future<String> fork(String sessionId, String fromEventId, {String? newId});

  /// 按 seq 顺序重放某会话的事件。日志不被改写。
  Future<void> replay(String sessionId, void Function(SessionEvent) handler);

  /// 列出所有已有会话 id（升序）。
  Future<List<String>> list();

  /// 释放后端资源。幂等。
  Future<void> close();
}

/// 校验并取出事件所属的会话 id；缺失时抛 [ArgumentError]。
String requireEventSessionId(SessionEvent event) {
  final String? sessionId = event.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw ArgumentError.value(
      event,
      'event',
      'SessionLog 要求事件带非空 sessionId',
    );
  }
  return sessionId;
}

/// 事件是否落在 [from] / [to] 的闭区间内。
bool eventInWindow(SessionEvent event, {DateTime? from, DateTime? to}) =>
    (from == null || !event.time.isBefore(from)) &&
    (to == null || !event.time.isAfter(to));

/// 取「截止 [fromEventId]（含）」的事件前缀；找不到时抛 [StateError]。
List<SessionEvent> eventPrefix(
  Iterable<SessionEvent> events,
  String fromEventId,
) {
  final List<SessionEvent> all = List<SessionEvent>.of(events);
  final int index =
      all.indexWhere((SessionEvent event) => event.id == fromEventId);
  if (index < 0) throw StateError('会话日志中不存在事件 "$fromEventId"');
  return all.sublist(0, index + 1);
}

/// 生成分叉会话的缺省 id，并前推 [counters] 里的会话计数。
String nextForkId(String sessionId, Map<String, int> counters) {
  final int count = (counters[sessionId] ?? 0) + 1;
  counters[sessionId] = count;
  return '$sessionId-fork-$count';
}

/// 为分叉前缀重新盖章：换成新会话 id，seq 从 0 起重新连续编号。
///
/// 事件 id 与 [SessionEvent.parentEventId] 原样保留，因此分叉会话与源会话共享
/// 的前缀仍可逐条对齐（重放终态一致）。
List<SessionEvent> restampPrefix(
  Iterable<SessionEvent> prefix,
  String newSessionId,
) =>
    <SessionEvent>[
      for (final (int index, SessionEvent event) in prefix.indexed)
        event.copyWith(seq: index, sessionId: newSessionId),
    ];
