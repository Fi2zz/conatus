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
        const TenantTagPolicy().filterFor(scope),
        queryVector: <double>[1, 0],
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
            const RagFilter(tenantId: 't1', anyTags: <String>{}),
            queryVector: <double>[1, 0],
            k: 10),
        isEmpty);
    expect(
        await backend.search(
            RagFilter(
                tenantId: 't1',
                includeTenantWide: true,
                from: DateTime.utc(2026, 6)),
            queryVector: <double>[1, 0],
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

  test('标签下推：租户级块按 includeTenantWide 放行，受限块按额外标签交集', () async {
    await backend.upsert(<RagChunk>[
      chunk('wide', 't1', <String>{'tenant:t1'}, 0),
      chunk('restricted', 't1', <String>{'tenant:t1', 'dept:hr'}, 1),
    ], <List<double>>[
      <double>[1, 0],
      <double>[1, 0],
    ]);

    Future<List<String>> ids(RagFilter filter) async => <String>[
          for (final RagHit h in await backend.search(filter,
              queryVector: <double>[1, 0], k: 10))
            h.chunk.id,
        ];

    // 租户级块在 includeTenantWide=false 时不放行（缺省）。
    expect(await ids(const RagFilter(tenantId: 't1', anyTags: <String>{})),
        isEmpty);
    // includeTenantWide=true 只放行租户级块，受限块仍被空标签拒绝。
    expect(
        await ids(const RagFilter(
            tenantId: 't1', anyTags: <String>{}, includeTenantWide: true)),
        <String>['wide']);
    // 额外标签交集命中受限块。
    expect(
        await ids(
            const RagFilter(tenantId: 't1', anyTags: <String>{'dept:hr'})),
        <String>['restricted']);
    // 无任何标签的过滤（anyTags=null）匹配租户内全部。
    expect(await ids(const RagFilter(tenantId: 't1')),
        <String>['restricted', 'wide']);
  });

  test('delete 按租户 + 额外标签只删受限块，租户级块保留', () async {
    await backend.upsert(<RagChunk>[
      chunk('wide', 't1', <String>{'tenant:t1'}, 0),
      chunk('restricted', 't1', <String>{'tenant:t1', 'dept:hr'}, 1),
    ], <List<double>>[
      <double>[1, 0],
      <double>[1, 0],
    ]);
    expect(
        await backend.delete(
            const RagFilter(tenantId: 't1', anyTags: <String>{'dept:hr'})),
        1);
    expect(await backend.count(), 1);
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
        const RagFilter(tenantId: 't1'),
        k: 10,
        queryVector: <double>[1, 0]);
    expect(hits.map((RagHit h) => h.chunk.id), <String>['a', 'b']);
  });

  test('upsert 维度与索引内已有向量不一致抛 ArgumentError', () async {
    await backend.upsert(<RagChunk>[
      chunk('a', 't1', {'tenant:t1'}, 0)
    ], <List<double>>[
      <double>[1, 0]
    ]);
    expect(
      () => backend.upsert(<RagChunk>[
        chunk('b', 't1', {'tenant:t1'}, 1)
      ], <List<double>>[
        <double>[1, 0, 0]
      ]),
      throwsArgumentError,
    );
    expect(await backend.count(), 1);
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
