import 'package:conatus_rag/conatus_rag.dart';
import 'package:test/test.dart';

import 'helpers/fixtures.dart';

class _Embedder implements Embedder {
  @override
  String get model => 'fake';
  @override
  int get dimension => 2;
  @override
  Future<List<double>> embed(String text) async => <double>[1, 0];
  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async =>
      <List<double>>[
        for (final String _ in texts) <double>[1, 0]
      ];
  @override
  void dispose() {}
}

class _ReversingReranker implements Reranker {
  @override
  Future<List<RagHit>> rerank(String query, List<RagHit> candidates,
      {required int topK}) async {
    final List<RagHit> reversed = candidates.reversed.toList();
    return reversed.take(topK).toList();
  }
}

class _ThrowingReranker implements Reranker {
  @override
  Future<List<RagHit>> rerank(String query, List<RagHit> candidates,
          {required int topK}) async =>
      throw StateError('rerank 端点挂了');
}

void main() {
  test('重排生效、预算截断、重排失败回退余弦', () async {
    final InMemoryRagBackend backend = InMemoryRagBackend();
    await backend.upsert(
      <RagChunk>[
        chunk('a', 't1', <String>{'tenant:t1'}, 0, text: '一' * 100),
        chunk('b', 't1', <String>{'tenant:t1'}, 1, text: '二' * 100),
      ],
      <List<double>>[
        <double>[1, 0],
        <double>[0.9, 0.1]
      ],
    );
    final RagScope scope = RagScope(tenantId: 't1');
    final RagFilter filter =
        RagFilter(tenantId: 't1', anyTags: scope.visibilityTags);
    final RetrievalRequest request = RetrievalRequest(
      query: 'q',
      scope: scope,
      tokenBudget: 60,
    );

    final DenseRetriever retriever = DenseRetriever(
      embedder: _Embedder(),
      backend: backend,
      reranker: _ReversingReranker(),
    );
    final List<RagHit> hits = await retriever.retrieve(request, filter);
    expect(hits.first.chunk.id, 'b');
    expect(
        hits.every((RagHit h) => estimateTokens(h.chunk.text) <= 60), isTrue);

    final DenseRetriever broken = DenseRetriever(
      embedder: _Embedder(),
      backend: backend,
      reranker: _ThrowingReranker(),
    );
    final List<RagHit> fallback = await broken.retrieve(request, filter);
    expect(fallback.first.chunk.id, 'a');
  });

  test('retriever 的 topK 作为硬上限截断请求 limit', () async {
    final InMemoryRagBackend backend = InMemoryRagBackend();
    await backend.upsert(
      <RagChunk>[
        chunk('a', 't1', <String>{'tenant:t1'}, 0, text: '一' * 10),
        chunk('b', 't1', <String>{'tenant:t1'}, 1, text: '二' * 10),
        chunk('c', 't1', <String>{'tenant:t1'}, 2, text: '三' * 10),
      ],
      <List<double>>[
        <double>[1, 0],
        <double>[0.9, 0.1],
        <double>[0.8, 0.2],
      ],
    );
    final RagScope scope = RagScope(tenantId: 't1');
    final RagFilter filter =
        RagFilter(tenantId: 't1', anyTags: scope.visibilityTags);
    final RetrievalRequest request = RetrievalRequest(
      query: 'q',
      scope: scope,
      limit: 10,
      tokenBudget: 1000,
    );

    final DenseRetriever retriever = DenseRetriever(
      embedder: _Embedder(),
      backend: backend,
      topK: 2,
    );
    final List<RagHit> hits = await retriever.retrieve(request, filter);
    expect(hits.length, 2);
  });
}
