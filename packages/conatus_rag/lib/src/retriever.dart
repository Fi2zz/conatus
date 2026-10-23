import 'embedder.dart';
import 'rag_backend.dart';
import 'rag_chunk.dart';
import 'rag_query.dart';
import 'reranker.dart';

/// 检索器契约：把检索请求与可见性过滤翻译为后端命中列表。
abstract interface class Retriever {
  Future<List<RagHit>> retrieve(RetrievalRequest request, RagFilter filter);
}

/// 基于嵌入 + 索引后端 + 可选重排的稠密检索器。
class DenseRetriever implements Retriever {
  DenseRetriever({
    required this.embedder,
    required this.backend,
    this.reranker = const NoopReranker(),
    this.candidates = 128,
    this.topK = 15,
    this.tokenBudget = 2000,
  });

  final Embedder embedder;
  final RagIndexBackend backend;
  final Reranker reranker;
  final int candidates;
  final int topK;
  final int tokenBudget;

  @override
  Future<List<RagHit>> retrieve(
    RetrievalRequest request,
    RagFilter filter,
  ) async {
    final List<double> vector = await embedder.embed(request.query);
    final RagFilter effective = mergeFilter(filter, request);
    final List<RagHit> found =
        await backend.search(effective, queryVector: vector, k: candidates);
    final List<RagHit> reranked = await _safeRerank(request.query, found);
    return applyBudget(reranked, request.limit, request.tokenBudget);
  }

  Future<List<RagHit>> _safeRerank(
    String query,
    List<RagHit> candidates,
  ) async {
    try {
      return await reranker.rerank(query, candidates, topK: candidates.length);
    } on Object {
      return candidates;
    }
  }
}

/// 把请求的 sourceIds / from / to 并入下游过滤条件（请求级收窄）。
RagFilter mergeFilter(RagFilter filter, RetrievalRequest request) {
  if (_noNarrowing(request)) return filter;
  return RagFilter(
    tenantId: filter.tenantId,
    anyTags: filter.anyTags,
    sourceIds: _mergeSourceIds(filter.sourceIds, request.sourceIds),
    from: _laterOf(filter.from, request.from),
    to: _earlierOf(filter.to, request.to),
  );
}

bool _noNarrowing(RetrievalRequest request) {
  if (request.sourceIds != null) return false;
  if (request.from != null) return false;
  return request.to == null;
}

Set<String>? _mergeSourceIds(Set<String>? filter, Set<String>? request) {
  if (filter == null) return request;
  if (request == null) return filter;
  return filter.intersection(request);
}

DateTime? _laterOf(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isAfter(b) ? a : b;
}

DateTime? _earlierOf(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isBefore(b) ? a : b;
}

/// 按 token 预算累加截断：至少保留 1 条，最终不超过 [topK]。
List<RagHit> applyBudget(List<RagHit> hits, int topK, int budget) {
  final List<RagHit> result = <RagHit>[];
  int used = 0;
  for (final RagHit hit in hits) {
    if (result.length >= topK) break;
    final int cost = estimateTokens(hit.chunk.text);
    if (used + cost > budget && result.isNotEmpty) break;
    result.add(hit);
    used += cost;
  }
  return result;
}
