/// session log 的装配：按可用后端挑选实现并提供为 `'sessionLog'` 服务。
library;

import 'dart:async';
import 'package:conatus_core/conatus_core.dart';
import 'database.dart';
import 'session_log.dart';
import 'session_log_database.dart';
import 'session_log_memory.dart';
import 'session_log_persistence.dart';
import 'session_persistence.dart';

/// `ctx.sessionLog`：当前上下文可见的 [SessionLog]。
extension SessionLogContext on Context {
  /// 取当前上下文可见的 [SessionLog]（未提供时抛 [StateError]）。
  SessionLog get sessionLog => require<SessionLog>('sessionLog');
}

/// 将 [SessionLog] 作为 `'sessionLog'` 服务提供到上下文。
///
/// 后端优先级：显式 [log] → [persistence]（或 `'sessionPersistence'` 服务，
/// 追加式，推荐用于长会话）→ [database]（或 `'database'` 服务，且至少注册了
/// 一个后端）→ 进程内 [InMemorySessionLog]。上下文释放时关闭日志。
SessionLog provideSessionLog(
  Context ctx, {
  SessionLog? log,
  SessionPersistence? persistence,
  Database? database,
}) {
  final SessionLog resolved = _resolveLog(ctx, log, persistence, database);
  ctx.provide('sessionLog', resolved);
  ctx.onDispose(() => unawaited(resolved.close()));
  return resolved;
}

SessionLog _resolveLog(
  Context ctx,
  SessionLog? log,
  SessionPersistence? persistence,
  Database? database,
) {
  if (log != null) return log;
  final SessionPersistence? store =
      persistence ?? ctx.get<SessionPersistence>('sessionPersistence');
  if (store != null) return PersistenceSessionLog(store);
  final Database? hub = database ?? ctx.get<Database>('database');
  if (hub != null && hub.backendNames.isNotEmpty) {
    return DatabaseSessionLog(hub);
  }
  return InMemorySessionLog();
}
