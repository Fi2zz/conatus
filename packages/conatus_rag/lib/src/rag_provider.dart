import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'rag_backend.dart';
import 'rag_config.dart';
import 'rag_evidence.dart';
import 'rag_index.dart';
import 'rag_scope.dart';
import 'rag_service.dart';
import 'rag_tool.dart';

/// 把 [RagService] 作为 `'rag'` 服务提供到上下文，并把 [RagSearchTool]
/// 注册进 `'tools'`（若上下文里已提供）。
///
/// [scope] 是本上下文内 `rag_search` 工具的检索作用域；为 null 时工具
/// fail closed。多租户宿主应为每个请求/租户建子上下文并传入对应 scope。
/// [log] 缺省取上下文里的 `'sessionLog'`；[backend] 缺省 [InMemoryRagBackend]。
RagService provideRag(
  Context ctx, {
  required RagConfig config,
  required ScopeResolver scopeOf,
  RagScope? scope,
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
  final ToolRegistry? tools = ctx.get<ToolRegistry>('tools');
  if (tools != null) {
    ctx.effect(
      () => tools.register(RagSearchTool(service: service, scope: scope)),
    );
  }
  return service;
}
