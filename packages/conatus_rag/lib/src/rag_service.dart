import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'rag_backend.dart';
import 'rag_chunk.dart';
import 'rag_config.dart';
import 'rag_evidence.dart';
import 'rag_index.dart';
import 'rag_query.dart';
import 'rag_scope.dart';
import 'rag_stats.dart';
import 'retriever.dart';
import 'visibility.dart';

/// RAG 服务：组合索引器、检索器与可见性策略。
class RagService {
  RagService({
    required RagIndexBackend backend,
    required RagConfig config,
    required ScopeResolver scopeOf,
    SessionLog? log,
    RetrievalObserver? audit,
  })  : _backend = backend,
        _config = config,
        _scopeOf = scopeOf,
        _audit = audit,
        _visibility = config.visibility,
        _indexer = log == null
            ? null
            : RagIndexer(
                backend: backend,
                embedder: config.embedder,
                log: log,
                scopeOf: scopeOf,
                chunking: ChunkerConfig(
                  chunkChars: config.chunkChars,
                  overlapChars: config.overlapChars,
                  maxChunkChars: config.maxChunkChars,
                ),
                indexVersion: config.indexVersion,
              );

  final RagIndexBackend _backend;
  final RagConfig _config;
  final ScopeResolver _scopeOf;
  final RetrievalObserver? _audit;
  final VisibilityPolicy _visibility;
  final RagIndexer? _indexer;

  int _retrievals = 0;
  int _emptyResults = 0;
  DateTime? _lastIngestAt;

  /// 后端只读访问，供测试与运维使用。
  RagIndexBackend get backend => _backend;

  /// 检索：可见性过滤 → 嵌入 → 后端搜索 → 二次过滤 → 审计。
  Future<List<RagHit>> retrieve(RetrievalRequest request) async {
    final Stopwatch sw = Stopwatch()..start();
    final List<RagHit> hits = await _retrieveCore(request);
    sw.stop();
    _audit?.call(_buildAudit(request, hits, sw.elapsedMilliseconds));
    return hits;
  }

  Future<List<RagHit>> _retrieveCore(RetrievalRequest request) async {
    await _ensureIngested();
    final RagFilter filter = _visibility.filterFor(request.scope);
    final DenseRetriever retriever = DenseRetriever(
      embedder: _config.embedder,
      backend: _backend,
      reranker: _config.reranker,
      candidates: _config.candidates,
      topK: _config.topK,
      tokenBudget: _config.tokenBudget,
    );
    final List<RagHit> found = await retriever.retrieve(request, filter);
    final List<RagHit> visible = found
        .where((RagHit h) => _visibility.allows(h.chunk, request.scope))
        .take(request.limit)
        .toList();
    _retrievals++;
    if (visible.isEmpty) _emptyResults++;
    return visible;
  }

  RetrievalAudit _buildAudit(
    RetrievalRequest request,
    List<RagHit> hits,
    int elapsedMs,
  ) =>
      RetrievalAudit(
        tenantId: request.scope.tenantId,
        principalId: request.scope.principalId,
        queryLength: request.query.length,
        hitIds: <String>[for (final RagHit h in hits) h.chunk.id],
        tokens: hits.fold<int>(
            0, (int sum, RagHit h) => sum + estimateTokens(h.chunk.text)),
        elapsedMs: elapsedMs,
      );

  Future<void> _ensureIngested() async {
    if (_indexer == null) return;
    await _indexer.ensureIngested();
    _lastIngestAt = DateTime.now();
  }

  /// 生成证据块：检索 → 格式化（不触发审计）。
  Future<String> evidenceBlock(
    String query,
    RagScope scope, {
    int? limit,
  }) async {
    final List<RagHit> hits = await _retrieveCore(RetrievalRequest(
      query: query,
      scope: scope,
      limit: limit ?? _config.injectLimit,
    ));
    return formatHits(hits);
  }

  /// 删除单个会话的切片；租户不匹配抛异常。
  Future<void> forgetSession(String sourceId, {required RagScope scope}) async {
    final RagScope resolved = await _scopeOf(sourceId);
    if (resolved.tenantId != scope.tenantId) {
      throw const RagException('rag_scope_denied', '来源归属与请求租户不一致');
    }
    await _backend.delete(RagFilter(
      tenantId: scope.tenantId,
      sourceIds: <String>{sourceId},
    ));
  }

  /// 删除作用域的切片；principal 不支持，显式拒绝。
  Future<void> forgetScope(RagScope scope) async {
    if (scope.principalId != null) {
      throw const RagException(
        'rag_principal_delete_unsupported',
        '暂不支持按用户身份删除',
      );
    }
    await _backend.delete(RagFilter(tenantId: scope.tenantId));
  }

  /// 重建索引；委托给内部索引器。
  Future<void> rebuild() async {
    if (_indexer == null) return;
    await _indexer.rebuild();
  }

  /// 统计：后端切片数 + 服务计数。
  Future<RagStats> stats() async {
    final int chunks = await _backend.count();
    return RagStats(
      chunks: chunks,
      retrievals: _retrievals,
      emptyResults: _emptyResults,
      rerankFallbacks: 0,
      embedFailures: 0,
      lastIngestAt: _lastIngestAt,
    );
  }
}

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
