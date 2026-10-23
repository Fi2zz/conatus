import 'package:conatus_foundation/conatus_foundation.dart';

import 'chunker.dart';
import 'embedder.dart';
import 'rag_backend.dart';
import 'rag_chunk.dart';
import 'rag_scope.dart';
import 'rag_snapshot.dart';
import 'rag_stats.dart';

/// 解析来源的作用域。
typedef ScopeResolver = Future<RagScope> Function(String sourceId);

/// 增量摄取与索引生命周期管理。
class RagIndexer {
  RagIndexer({
    required RagIndexBackend backend,
    required Embedder embedder,
    required SessionLog log,
    required ScopeResolver scopeOf,
    required ChunkerConfig chunking,
    required int indexVersion,
  })  : _backend = backend,
        _embedder = embedder,
        _log = log,
        _scopeOf = scopeOf,
        _chunking = chunking,
        _indexVersion = indexVersion;

  final RagIndexBackend _backend;
  final Embedder _embedder;
  final SessionLog _log;
  final ScopeResolver _scopeOf;
  final ChunkerConfig _chunking;
  final int _indexVersion;

  RagIndexBackend get backend => _backend;
  Embedder get embedder => _embedder;

  RagSnapshotMeta _expectedMeta() => RagSnapshotMeta(
        embeddingModel: _embedder.model,
        dimension: _embedder.dimension,
        indexVersion: _indexVersion,
      );

  Future<void> _ensureMeta() async {
    final RagSnapshotMeta? current = await _backend.meta();
    if (current == null) {
      await _backend.init(_expectedMeta());
      return;
    }
    if (!current.matches(_expectedMeta())) {
      throw const RagException('rag_index_stale', '索引元信息与当前配置不一致');
    }
  }

  /// 摄取单个会话；返回新增切片数。
  Future<int> ingestSession(String sourceId) async {
    if (await _backend.sourceForgotten(sourceId)) return 0;
    final RagScope scope = await _resolveScope(sourceId);
    await _ensureMeta();
    final RagCursor? cursor = await _backend.cursorOf(sourceId);
    final int lastSeq = cursor?.lastSeq ?? -1;
    final List<SessionEvent> events = await _readNewEvents(sourceId, lastSeq);
    if (events.isEmpty) return 0;
    return await _chunkEmbedUpsert(scope, sourceId, events);
  }

  Future<RagScope> _resolveScope(String sourceId) async {
    try {
      return await _scopeOf(sourceId);
    } on Object {
      throw const RagException('rag_scope_unresolved', '无法解析来源作用域');
    }
  }

  Future<List<SessionEvent>> _readNewEvents(
      String sourceId, int lastSeq) async {
    final List<SessionEvent> result = <SessionEvent>[];
    await for (final SessionEvent event in _log.read(sourceId)) {
      if (event.seq > lastSeq) result.add(event);
    }
    return result;
  }

  Future<int> _chunkEmbedUpsert(
    RagScope scope,
    String sourceId,
    List<SessionEvent> events,
  ) async {
    final RagSource source = RagSource(
      sourceKind: 'session',
      sourceId: sourceId,
      scope: scope,
    );
    final List<RagChunk> chunks = chunkEvents(source, events, _chunking);
    if (chunks.isNotEmpty) {
      final List<List<double>> vectors = await _embed(chunks);
      await _backend.upsert(chunks, vectors);
    }
    await _backend.saveCursor(RagCursor(
      tenantId: scope.tenantId,
      sourceId: sourceId,
      lastSeq: events.last.seq,
    ));
    return chunks.length;
  }

  Future<List<List<double>>> _embed(List<RagChunk> chunks) async {
    try {
      return await _embedder
          .embedBatch(<String>[for (final RagChunk c in chunks) c.text]);
    } on Object {
      throw const RagException('rag_embed_failed', '嵌入批次失败');
    }
  }

  /// 摄取所有会话；返回新增切片总数。
  Future<int> ingestAll() async {
    final List<String> ids = await _log.list();
    int total = 0;
    for (final String id in ids) {
      total += await _ingestOne(id);
    }
    return total;
  }

  Future<int> _ingestOne(String id) async {
    try {
      return await ingestSession(id);
    } on RagException catch (error) {
      if (error.code == 'rag_index_stale') rethrow;
      return 0;
    }
  }

  /// 同 [ingestAll]，命名上表达幂等语义。
  Future<void> ensureIngested() async {
    await ingestAll();
  }

  /// 清空并重建索引。
  Future<void> rebuild() async {
    await _backend.clear();
    await _backend.init(_expectedMeta());
    await ingestAll();
  }
}
