import 'package:conatus_foundation/conatus_foundation.dart';

import 'rag_backend.dart';
import 'rag_chunk.dart';
import 'rag_config.dart';
import 'rag_evidence.dart' as evidence;
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
    evidence.RetrievalObserver? audit,
    Logger? logger,
  })  : _backend = backend,
        _config = config,
        _scopeOf = scopeOf,
        _audit = audit,
        _logger = logger,
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
  final evidence.RetrievalObserver? _audit;
  final Logger? _logger;
  final VisibilityPolicy _visibility;
  final RagIndexer? _indexer;

  int _retrievals = 0;
  int _emptyResults = 0;
  int _rerankFallbacks = 0;
  int _embedFailures = 0;
  DateTime? _lastIngestAt;

  /// 后端只读访问，供测试与运维使用。
  RagIndexBackend get backend => _backend;

  /// 摄入失败的来源数（由内部索引器聚合）。
  int get ingestFailures => _indexer?.ingestFailures ?? 0;

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
      onRerankFallback: _onRerankFallback,
    );
    final List<RagHit> found;
    try {
      found = await retriever.retrieve(request, filter);
    } on RagException catch (error) {
      if (error.code == 'rag_embed_failed') {
        _embedFailures++;
        _logCode('rag_embed_failed');
      }
      rethrow;
    }
    final List<RagHit> visible = found
        .where((RagHit h) => _visibility.allows(h.chunk, request.scope))
        .take(request.limit)
        .toList();
    _retrievals++;
    if (visible.isEmpty) _emptyResults++;
    return visible;
  }

  evidence.RetrievalAudit _buildAudit(
    RetrievalRequest request,
    List<RagHit> hits,
    int elapsedMs,
  ) =>
      evidence.RetrievalAudit(
        tenantId: request.scope.tenantId,
        principalId: request.scope.principalId,
        queryLength: request.query.length,
        hitIds: <String>[for (final RagHit h in hits) h.chunk.id],
        tokens: hits.fold<int>(
            0, (int sum, RagHit h) => sum + estimateTokens(h.chunk.text)),
        elapsedMs: elapsedMs,
      );

  Future<void> _ensureIngested() async {
    final RagIndexer? indexer = _indexer;
    if (indexer == null) return;
    final int before = indexer.ingestFailures;
    try {
      await indexer.ensureIngested();
    } on RagException catch (error) {
      if (error.code == 'rag_index_stale') _logCode('rag_index_stale');
      rethrow;
    }
    if (indexer.ingestFailures > before) {
      _logCode('rag_embed_failed');
    }
    _lastIngestAt = DateTime.now();
  }

  /// 懒补齐（幂等）；未配置 [SessionLog] 时为空操作。
  Future<void> ensureIngested() => _ensureIngested();

  /// 摄取单个会话；未配置 [SessionLog] 时不可用。
  Future<int> ingestSession(String sourceId) async {
    final RagIndexer? indexer = _indexer;
    if (indexer == null) {
      throw const RagException('rag_ingest_unavailable', '未配置 SessionLog');
    }
    try {
      return await indexer.ingestSession(sourceId);
    } on RagException catch (error) {
      if (error.code == 'rag_index_stale') _logCode('rag_index_stale');
      rethrow;
    }
  }

  /// 摄取全部会话；未配置 [SessionLog] 时不可用。
  Future<int> ingestAll() async {
    final RagIndexer? indexer = _indexer;
    if (indexer == null) {
      throw const RagException('rag_ingest_unavailable', '未配置 SessionLog');
    }
    try {
      return await indexer.ingestAll();
    } on RagException catch (error) {
      if (error.code == 'rag_index_stale') _logCode('rag_index_stale');
      rethrow;
    }
  }

  /// 生成证据块：走与工具一致的检索路径（含审计）。
  Future<String> evidenceBlock(
    String query,
    RagScope scope, {
    int? limit,
  }) async {
    final List<RagHit> hits = await retrieve(RetrievalRequest(
      query: query,
      scope: scope,
      limit: limit ?? _config.injectLimit,
    ));
    return formatHits(hits);
  }

  /// 把命中列表格式化为证据块（与顶层 [evidence.formatHits] 同格式）。
  String formatHits(List<RagHit> hits) => evidence.formatHits(hits);

  /// 删除单个会话的切片；租户不匹配抛异常。返回删除块数。
  ///
  /// 一旦遗忘，该来源在显式 [clear] 之前不再回到索引（[RagIndexer.rebuild]
  /// 保留遗忘集合），后续新增事件也不会让它复活。
  Future<int> forgetSession(String sourceId, {required RagScope scope}) async {
    final RagScope resolved;
    try {
      resolved = await _scopeOf(sourceId);
    } on Object {
      _logCode('rag_scope_unresolved');
      throw const RagException('rag_scope_unresolved', '无法解析来源作用域');
    }
    if (resolved.tenantId != scope.tenantId) {
      throw const RagException('rag_scope_denied', '来源归属与请求租户不一致');
    }
    return _backend.delete(RagFilter(
      tenantId: scope.tenantId,
      sourceIds: <String>{sourceId},
    ));
  }

  /// 删除作用域的切片；principal 不支持，显式拒绝。返回删除块数。
  Future<int> forgetScope(RagScope scope) async {
    if (scope.principalId != null) {
      throw const RagException(
        'rag_principal_delete_unsupported',
        '暂不支持按用户身份删除',
      );
    }
    return _backend.delete(RagFilter(tenantId: scope.tenantId));
  }

  /// 清空全部索引与游标（运维动作，需宿主鉴权）。
  Future<void> clear() => _backend.clear();

  /// 重建索引；委托给内部索引器。
  Future<void> rebuild() async {
    final RagIndexer? indexer = _indexer;
    if (indexer == null) return;
    try {
      await indexer.rebuild();
    } on RagException catch (error) {
      if (error.code == 'rag_index_stale') _logCode('rag_index_stale');
      rethrow;
    }
  }

  /// 统计：后端切片数 + 服务计数。`embedFailures` 汇总查询侧嵌入失败与摄入侧
  /// 失败（摄入侧以 [RagIndexer.ingestFailures] 计，因其以嵌入失败为主）。
  Future<RagStats> stats() async {
    final int chunks = await _backend.count();
    return RagStats(
      chunks: chunks,
      retrievals: _retrievals,
      emptyResults: _emptyResults,
      rerankFallbacks: _rerankFallbacks,
      embedFailures: _embedFailures + (_indexer?.ingestFailures ?? 0),
      lastIngestAt: _lastIngestAt,
    );
  }

  void _onRerankFallback() {
    _rerankFallbacks++;
  }

  /// 只记录错误码，绝不落查询原文或证据正文。
  void _logCode(String code) => _logger?.error(code);
}
