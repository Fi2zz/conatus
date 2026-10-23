import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'rag_backend.dart';
import 'rag_config.dart';
import 'rag_evidence.dart';
import 'rag_index.dart';
import 'rag_service.dart';

/// 把 [RagService] 作为 `'rag'` 服务提供到上下文。
///
/// [log] 缺省取上下文里的 `'sessionLog'`；[backend] 缺省 [InMemoryRagBackend]。
/// 工具注册在后续任务完成，本函数不注册。
RagService provideRag(
  Context ctx, {
  required RagConfig config,
  required ScopeResolver scopeOf,
  RagIndexBackend? backend,
  SessionLog? log,
  RetrievalObserver? audit,
}) {
  final RagService service = RagService(
    backend: backend ?? InMemoryRagBackend(),
    config: config,
    scopeOf: scopeOf,
    log: log ?? ctx.require<SessionLog>('sessionLog'),
    audit: audit,
  );
  ctx.provide('rag', service);
  return service;
}
