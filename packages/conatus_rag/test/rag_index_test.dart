import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_rag/conatus_rag.dart';
import 'package:test/test.dart';

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

class _ThrowingEmbedder implements Embedder {
  @override
  String get model => 'broken';
  @override
  int get dimension => 2;
  @override
  Future<List<double>> embed(String text) async =>
      throw const RagException('rag_embed_failed', '嵌入失败');
  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async =>
      throw const RagException('rag_embed_failed', '嵌入失败');
  @override
  void dispose() {}
}

void main() {
  group('RagIndexer', () {
    test('重复摄取幂等，新事件增量，失败不推进游标', () async {
      final InMemorySessionLog log = InMemorySessionLog();
      await log.append(SessionEvent.create(
          sessionId: 's1',
          seq: 0,
          type: kUserMessageEvent,
          data: <String, Object?>{'text': '事实 A'}));
      final InMemoryRagBackend backend = InMemoryRagBackend();
      final RagIndexer indexer = RagIndexer(
          backend: backend,
          embedder: _Embedder(),
          log: log,
          scopeOf: (String id) async => RagScope(tenantId: 't1'),
          chunking: const ChunkerConfig(
              chunkChars: 700, overlapChars: 90, maxChunkChars: 1200),
          indexVersion: 1);
      expect(await indexer.ingestSession('s1'), 1);
      expect(await indexer.ingestSession('s1'), 0);
      await log.append(SessionEvent.create(
          sessionId: 's1',
          seq: 1,
          type: kAssistantMessageEvent,
          data: <String, Object?>{'text': '收到'}));
      expect(await indexer.ingestSession('s1'), greaterThan(0));

      final RagIndexer failing = RagIndexer(
          backend: InMemoryRagBackend(),
          embedder: _ThrowingEmbedder(),
          log: log,
          scopeOf: (String id) async => RagScope(tenantId: 't1'),
          chunking: const ChunkerConfig(
              chunkChars: 700, overlapChars: 90, maxChunkChars: 1200),
          indexVersion: 1);
      await expectLater(
          failing.ingestSession('s1'), throwsA(isA<RagException>()));
      expect(await failing.backend.cursorOf('s1'), isNull);
    });

    test('forget 后 ingestSession 不再重新摄入（遗忘墓碑）', () async {
      final InMemorySessionLog log = InMemorySessionLog();
      await log.append(SessionEvent.create(
          sessionId: 's1',
          seq: 0,
          type: kUserMessageEvent,
          data: <String, Object?>{'text': '事实 A'}));
      final InMemoryRagBackend backend = InMemoryRagBackend();
      final RagIndexer indexer = RagIndexer(
          backend: backend,
          embedder: _Embedder(),
          log: log,
          scopeOf: (String id) async => RagScope(tenantId: 't1'),
          chunking: const ChunkerConfig(
              chunkChars: 700, overlapChars: 90, maxChunkChars: 1200),
          indexVersion: 1);
      expect(await indexer.ingestSession('s1'), 1);
      await backend
          .delete(const RagFilter(tenantId: 't1', sourceIds: <String>{'s1'}));
      expect(await backend.sourceForgotten('s1'), isTrue);
      expect(await indexer.ingestSession('s1'), 0);
      expect(await backend.count(), 0);
    });

    test('rebuild 保留遗忘集合，遗忘来源不被复活', () async {
      final InMemorySessionLog log = InMemorySessionLog();
      await log.append(SessionEvent.create(
          sessionId: 's1',
          seq: 0,
          type: kUserMessageEvent,
          data: <String, Object?>{'text': '事实 A'}));
      final InMemoryRagBackend backend = InMemoryRagBackend();
      final RagIndexer indexer = RagIndexer(
          backend: backend,
          embedder: _Embedder(),
          log: log,
          scopeOf: (String id) async => RagScope(tenantId: 't1'),
          chunking: const ChunkerConfig(
              chunkChars: 700, overlapChars: 90, maxChunkChars: 1200),
          indexVersion: 1);
      expect(await indexer.ingestSession('s1'), 1);
      await backend
          .delete(const RagFilter(tenantId: 't1', sourceIds: <String>{'s1'}));
      expect(await backend.sourceForgotten('s1'), isTrue);

      await indexer.rebuild();
      expect(await backend.count(), 0);
      expect(await backend.sourceForgotten('s1'), isTrue);
      expect(await indexer.ingestSession('s1'), 0);
    });

    test('clear 清空遗忘集合后来源可再次摄入', () async {
      final InMemorySessionLog log = InMemorySessionLog();
      await log.append(SessionEvent.create(
          sessionId: 's1',
          seq: 0,
          type: kUserMessageEvent,
          data: <String, Object?>{'text': '事实 A'}));
      final InMemoryRagBackend backend = InMemoryRagBackend();
      final RagIndexer indexer = RagIndexer(
          backend: backend,
          embedder: _Embedder(),
          log: log,
          scopeOf: (String id) async => RagScope(tenantId: 't1'),
          chunking: const ChunkerConfig(
              chunkChars: 700, overlapChars: 90, maxChunkChars: 1200),
          indexVersion: 1);
      expect(await indexer.ingestSession('s1'), 1);
      await backend
          .delete(const RagFilter(tenantId: 't1', sourceIds: <String>{'s1'}));
      expect(await backend.sourceForgotten('s1'), isTrue);

      await backend.clear();
      expect(await backend.sourceForgotten('s1'), isFalse);
      expect(await indexer.ingestSession('s1'), 1);
      expect(await backend.count(), 1);
    });
  });
}
