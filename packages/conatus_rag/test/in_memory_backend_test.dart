import 'package:conatus_rag/conatus_rag.dart';
import 'package:test/test.dart';

import 'helpers/fixtures.dart';

void main() {
  late InMemoryRagBackend backend;
  setUp(() => backend = InMemoryRagBackend());

  test('按租户与标签过滤，跨租户不可见', () async {
    await backend.upsert(<RagChunk>[
      chunk('a', 't1', <String>{'tenant:t1', 'dept:fin'}, 0),
      chunk('b', 't2', <String>{'tenant:t2'}, 1),
    ], <List<double>>[
      <double>[1, 0],
      <double>[1, 0],
    ]);
    final RagScope scope =
        RagScope(tenantId: 't1', visibilityTags: {'dept:fin'});
    final List<RagHit> hits = await backend.search(
        RetrievalRequest(query: 'q', scope: scope),
        RagFilter(tenantId: 't1', anyTags: scope.visibilityTags),
        k: 10);
    expect(hits.map((RagHit h) => h.chunk.id), <String>['a']);
  });

  test('空标签与时间窗过滤', () async {
    await backend.upsert(<RagChunk>[
      chunk('a', 't1', <String>{'tenant:t1'}, 0, time: DateTime.utc(2026)),
    ], <List<double>>[
      <double>[1, 0]
    ]);
    expect(
        await backend.search(
            RetrievalRequest(query: 'q', scope: RagScope(tenantId: 't1')),
            const RagFilter(tenantId: 't1', anyTags: <String>{}),
            k: 10),
        isEmpty);
    expect(
        await backend.search(
            RetrievalRequest(query: 'q', scope: RagScope(tenantId: 't1')),
            RagFilter(
                tenantId: 't1',
                anyTags: {'tenant:t1'},
                from: DateTime.utc(2026, 6)),
            k: 10),
        isEmpty);
  });

  test('meta、游标、delete 连带清游标、count', () async {
    const RagSnapshotMeta meta =
        RagSnapshotMeta(embeddingModel: 'e', dimension: 2, indexVersion: 1);
    await backend.init(meta);
    await backend.init(meta);
    expect((await backend.meta())!.embeddingModel, 'e');
    expect(
        () => backend.init(const RagSnapshotMeta(
            embeddingModel: 'other', dimension: 2, indexVersion: 1)),
        throwsA(isA<RagException>()));
    await backend.upsert(<RagChunk>[
      chunk('a', 't1', {'tenant:t1'}, 0)
    ], <List<double>>[
      <double>[1, 0]
    ]);
    await backend.saveCursor(
        const RagCursor(tenantId: 't1', sourceId: 's0', lastSeq: 0));
    expect(await backend.count(), 1);
    expect(
        await backend
            .delete(const RagFilter(tenantId: 't1', sourceIds: <String>{'s0'})),
        1);
    expect(await backend.count(), 0);
    expect(await backend.cursorOf('s0'), isNull);
  });

  test('同分按 chunk id 升序，与插入顺序无关', () async {
    await backend.upsert(<RagChunk>[
      chunk('b', 't1', <String>{'tenant:t1'}, 1),
      chunk('a', 't1', <String>{'tenant:t1'}, 0),
    ], <List<double>>[
      <double>[1, 0],
      <double>[1, 0]
    ]);
    final List<RagHit> hits = await backend.search(
        RetrievalRequest(query: 'q', scope: RagScope(tenantId: 't1')),
        const RagFilter(tenantId: 't1'),
        k: 10,
        queryVector: <double>[1, 0]);
    expect(hits.map((RagHit h) => h.chunk.id), <String>['a', 'b']);
  });

  test('upsert 长度不一致抛 ArgumentError', () async {
    expect(
      () => backend.upsert(<RagChunk>[
        chunk('a', 't1', {'tenant:t1'}, 0)
      ], const <List<double>>[]),
      throwsArgumentError,
    );
  });

  test('delete 只清匹配来源的游标，其他租户与来源保留', () async {
    await backend.saveCursor(
        const RagCursor(tenantId: 't1', sourceId: 's0', lastSeq: 0));
    await backend.saveCursor(
        const RagCursor(tenantId: 't1', sourceId: 's1', lastSeq: 1));
    await backend.saveCursor(
        const RagCursor(tenantId: 't2', sourceId: 's2', lastSeq: 2));
    await backend
        .delete(const RagFilter(tenantId: 't1', sourceIds: <String>{'s0'}));
    expect(await backend.cursorOf('s0'), isNull);
    expect(await backend.cursorOf('s1'), isNotNull);
    expect(await backend.cursorOf('s2'), isNotNull);
  });

  test('clear 清空索引、游标与 meta', () async {
    const RagSnapshotMeta meta =
        RagSnapshotMeta(embeddingModel: 'e', dimension: 2, indexVersion: 1);
    await backend.init(meta);
    await backend.upsert(<RagChunk>[
      chunk('a', 't1', {'tenant:t1'}, 0)
    ], <List<double>>[
      <double>[1, 0]
    ]);
    await backend.saveCursor(
        const RagCursor(tenantId: 't1', sourceId: 's0', lastSeq: 0));
    await backend.clear();
    expect(await backend.count(), 0);
    expect(await backend.cursorOf('s0'), isNull);
    expect(await backend.meta(), isNull);
  });
}
