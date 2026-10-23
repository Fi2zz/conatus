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
      expect(audits.single.tokens, estimateTokens('用户：我的订单号是 A-1024'));
    });

    test('forgetSession/forgetScope 返回删除块数并校验租户与 principal', () async {
      final InMemoryRagBackend backend = InMemoryRagBackend();
      await backend.upsert(
        <RagChunk>[
          chunk('a', 't1', <String>{'tenant:t1'}, 0),
          chunk('b', 't1', <String>{'tenant:t1'}, 1),
        ],
        <List<double>>[
          <double>[1, 0],
          <double>[1, 0],
        ],
      );
      final RagService service = RagService(
        backend: backend,
        config: RagConfig(embedder: _FakeEmbedder()),
        scopeOf: (String id) async => RagScope(tenantId: 't1'),
      );
      expect(await service.forgetSession('s0', scope: RagScope(tenantId: 't1')),
          1);
      expect(await service.forgetSession('s0', scope: RagScope(tenantId: 't1')),
          0);
      expect(await service.backend.count(), 1);
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
      expect(await service.forgetScope(RagScope(tenantId: 't1')), 1);
      expect(await service.backend.count(), 0);
    });

    test('clear 清空全部索引', () async {
      final InMemoryRagBackend backend = InMemoryRagBackend();
      await backend.upsert(
        <RagChunk>[
          chunk('a', 't1', <String>{'tenant:t1'}, 0)
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
      await service.clear();
      expect(await service.backend.count(), 0);
    });

    test('stats 反映后端计数与服务计数', () async {
      final InMemoryRagBackend backend = InMemoryRagBackend();
      await backend.upsert(
        <RagChunk>[
          chunk('a', 't1', <String>{'tenant:t1'}, 0, text: '订单 A'),
          chunk('b', 't1', <String>{'tenant:t1'}, 1, text: '订单 B'),
        ],
        <List<double>>[
          <double>[1, 0],
          <double>[1, 0],
        ],
      );
      final RagService service = RagService(
        backend: backend,
        config: RagConfig(embedder: _FakeEmbedder()),
        scopeOf: (String id) async => RagScope(tenantId: 't1'),
      );
      expect((await service.stats()).chunks, 2);
      await service.retrieve(
        RetrievalRequest(query: '订单', scope: RagScope(tenantId: 't1')),
      );
      expect((await service.stats()).retrievals, 1);
    });

    test('formatHits 空、按时间升序、时间格式与 id 去重', () {
      expect(formatHits(const <RagHit>[]), '');
      final RagChunk early = chunk('b', 't1', <String>{'tenant:t1'}, 0,
          text: '较早', startTime: DateTime.utc(2026, 10, 20, 14, 3));
      final RagChunk late = chunk('a', 't1', <String>{'tenant:t1'}, 1,
          text: '较晚', startTime: DateTime.utc(2026, 10, 21, 9, 5));
      final RagChunk dup = chunk('b', 't1', <String>{'tenant:t1'}, 2,
          text: '重复', startTime: DateTime.utc(2026, 10, 22, 1, 2));
      final String block = formatHits(<RagHit>[
        RagHit(chunk: late, score: 1),
        RagHit(chunk: early, score: 1),
        RagHit(chunk: dup, score: 1),
      ]);
      expect(block, contains('[2026-10-20 14:03]'));
      expect(block, contains('[2026-10-21 09:05]'));
      expect(block, isNot(contains('[2026-10-22 01:02]')));
      expect(block, contains('较早'));
      expect(block, contains('较晚'));
      expect(block, isNot(contains('重复')));
      expect(block.indexOf('较早'), lessThan(block.indexOf('较晚')));
    });

    test('log 为 null 时 ensureIngested 空操作，ingestSession 显式不可用', () async {
      final RagService service = RagService(
        backend: InMemoryRagBackend(),
        config: RagConfig(embedder: _FakeEmbedder()),
        scopeOf: (String id) async => RagScope(tenantId: 't1'),
      );
      await service.ensureIngested();
      await expectLater(
        service.ingestSession('s0'),
        throwsA(
          isA<RagException>().having(
            (RagException e) => e.code,
            'code',
            'rag_ingest_unavailable',
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
  DateTime? startTime,
}) =>
    RagChunk(
      id: id,
      tenantId: tenant,
      sourceKind: 'session',
      sourceId: 's$seq',
      firstSeq: seq,
      lastSeq: seq,
      eventIds: <String>{'e$seq'},
      startTime: startTime ?? DateTime.utc(2026, 10, 20, 14, 3),
      endTime: startTime ?? DateTime.utc(2026, 10, 20, 14, 3),
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
