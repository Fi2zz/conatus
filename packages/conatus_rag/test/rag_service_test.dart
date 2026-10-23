import 'package:conatus_rag/conatus_rag.dart';
import 'package:test/test.dart';

void main() {
  group('RagService', () {
    test('检索走策略过滤，审计不含正文，注入块带 citation', () async {
      final InMemoryRagBackend backend = InMemoryRagBackend();
      await backend.upsert(
        <RagChunk>[
          chunk('a', 't1', <String>{'tenant:t1'}, 0, text: '用户：我的订单号是 A-1024'),
          chunk('b', 't2', <String>{'tenant:t2'}, 1, text: '用户：别人的订单号是 B-2048'),
        ],
        <List<double>>[
          <double>[1, 0],
          <double>[1, 0],
        ],
      );
      final List<RetrievalAudit> audits = <RetrievalAudit>[];
      final RagService service = RagService(
        backend: backend,
        config: RagConfig(embedder: _FakeEmbedder()),
        scopeOf: (String id) async => RagScope(tenantId: 't1'),
        audit: audits.add,
      );
      final RagScope scope = RagScope(tenantId: 't1');
      final List<RagHit> hits = await service.retrieve(
        RetrievalRequest(query: '订单号', scope: scope),
      );
      expect(hits.map((RagHit h) => h.chunk.id), <String>['a']);
      final String block = await service.evidenceBlock('订单号', scope);
      expect(block, contains('[相关历史证据]'));
      expect(block, contains('session:s0 seq:0-0'));
      expect(audits.single.tenantId, 't1');
      expect(audits.single.hitIds, <String>['a']);
    });

    test('forgetSession 校验租户，forgetScope(principal) 显式拒绝', () async {
      final InMemoryRagBackend backend = InMemoryRagBackend();
      await backend.upsert(
        <RagChunk>[
          chunk('a', 't1', <String>{'tenant:t1'}, 0),
        ],
        <List<double>>[
          <double>[1, 0]
        ],
      );
      final RagService service = RagService(
        backend: backend,
        config: RagConfig(embedder: _FakeEmbedder()),
        scopeOf: (String id) async => RagScope(tenantId: 't1'),
      );
      await service.forgetSession('s0', scope: RagScope(tenantId: 't1'));
      expect(await service.backend.count(), 0);
      await expectLater(
        service.forgetSession('s0', scope: RagScope(tenantId: 't2')),
        throwsA(isA<RagException>()),
      );
      await expectLater(
        service.forgetScope(RagScope(tenantId: 't1', principalId: 'u1')),
        throwsA(
          isA<RagException>().having(
            (RagException e) => e.code,
            'code',
            'rag_principal_delete_unsupported',
          ),
        ),
      );
    });
  });
}

RagChunk chunk(
  String id,
  String tenant,
  Set<String> tags,
  int seq, {
  String text = '正文',
}) =>
    RagChunk(
      id: id,
      tenantId: tenant,
      sourceKind: 'session',
      sourceId: 's$seq',
      firstSeq: seq,
      lastSeq: seq,
      eventIds: <String>{'e$seq'},
      startTime: DateTime.utc(2026, 10, 20, 14, 3),
      endTime: DateTime.utc(2026, 10, 20, 14, 3),
      text: text,
      visibilityTags: tags,
    );

class _FakeEmbedder implements Embedder {
  @override
  String get model => 'fake';

  @override
  int get dimension => 2;

  @override
  Future<List<double>> embed(String text) async => <double>[1, 0];

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async =>
      <List<double>>[
        for (final String _ in texts) <double>[1, 0],
      ];

  @override
  void dispose() {}
}
