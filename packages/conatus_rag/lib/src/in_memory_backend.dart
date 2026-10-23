import 'cosine.dart';
import 'rag_backend.dart';
import 'rag_chunk.dart';
import 'rag_query.dart';
import 'rag_snapshot.dart';
import 'rag_stats.dart';

bool _cursorMatches(RagCursor cursor, RagFilter filter) {
  if (cursor.tenantId != filter.tenantId) {
    return false;
  }
  return filter.sourceIds == null ||
      filter.sourceIds!.contains(cursor.sourceId);
}

class _Scored {
  const _Scored(this.chunk, this.score);

  final RagChunk chunk;
  final double score;
}

int _compareScored(_Scored a, _Scored b) {
  final int byScore = b.score.compareTo(a.score);
  if (byScore != 0) {
    return byScore;
  }
  return a.chunk.id.compareTo(b.chunk.id);
}

/// 内存参考实现，适合测试与万级以下的块规模。
class InMemoryRagBackend implements RagIndexBackend {
  RagSnapshotMeta? _meta;
  final Map<String, RagChunk> _chunks = <String, RagChunk>{};
  final Map<String, List<double>> _vectors = <String, List<double>>{};
  final Map<String, RagCursor> _cursors = <String, RagCursor>{};
  final Set<String> _forgotten = <String>{};

  @override
  Future<RagSnapshotMeta?> meta() async => _meta;

  @override
  Future<void> init(RagSnapshotMeta meta) async {
    final RagSnapshotMeta? current = _meta;
    if (current == null) {
      _meta = meta;
      return;
    }
    if (!current.matches(meta)) {
      throw const RagException('rag_index_stale', '索引元信息与当前配置不一致，需先清空后重建');
    }
  }

  @override
  Future<List<RagHit>> search(
    RagFilter filter, {
    required List<double> queryVector,
    required int k,
  }) async {
    final List<_Scored> scored = <_Scored>[
      for (final RagChunk chunk in _chunks.values)
        if (chunkMatches(chunk, filter))
          _Scored(chunk, cosineSimilarity(queryVector, _vectors[chunk.id]!)),
    ]..sort(_compareScored);
    return <RagHit>[
      for (final _Scored item in scored.take(k))
        RagHit(chunk: item.chunk, score: item.score),
    ];
  }

  @override
  Future<void> upsert(List<RagChunk> chunks, List<List<double>> vectors) async {
    if (chunks.length != vectors.length) {
      throw ArgumentError('切片与向量数量不一致：${chunks.length} != ${vectors.length}');
    }
    _checkDimensions(vectors);
    for (int i = 0; i < chunks.length; i++) {
      _chunks[chunks[i].id] = chunks[i];
      _vectors[chunks[i].id] = List<double>.unmodifiable(vectors[i]);
    }
  }

  void _checkDimensions(List<List<double>> vectors) {
    if (vectors.isEmpty) {
      return;
    }
    final int expected =
        _vectors.isEmpty ? vectors.first.length : _vectors.values.first.length;
    for (final List<double> vector in vectors) {
      if (vector.length != expected) {
        throw ArgumentError('向量维度应为 $expected，实际为 ${vector.length}');
      }
    }
  }

  @override
  Future<int> delete(RagFilter filter) async {
    final List<String> ids = <String>[
      for (final RagChunk chunk in _chunks.values)
        if (chunkMatches(chunk, filter)) chunk.id,
    ];
    final Set<String> forgotten = <String>{
      for (final String id in ids) _chunks[id]!.sourceId,
    };
    for (final String id in ids) {
      _chunks.remove(id);
      _vectors.remove(id);
    }
    final List<String> cursorSources = <String>[
      for (final MapEntry<String, RagCursor> entry in _cursors.entries)
        if (_cursorMatches(entry.value, filter)) entry.key,
    ];
    for (final String sourceId in cursorSources) {
      _cursors.remove(sourceId);
    }
    forgotten.addAll(cursorSources);
    _forgotten.addAll(forgotten);
    return ids.length;
  }

  @override
  Future<int> count() async => _chunks.length;

  @override
  Future<void> clear() async {
    _chunks.clear();
    _vectors.clear();
    _cursors.clear();
    _forgotten.clear();
    _meta = null;
  }

  RagSnapshot snapshot() => RagSnapshot(
        meta: _meta,
        chunks: _chunks.values.toList(),
        vectors: <List<double>>[
          for (final RagChunk chunk in _chunks.values) _vectors[chunk.id]!,
        ],
        cursors: _cursors.values.toList(),
        forgotten: Set<String>.from(_forgotten),
      );

  @override
  Future<RagCursor?> cursorOf(String sourceId) async => _cursors[sourceId];

  @override
  Future<void> saveCursor(RagCursor cursor) async {
    _cursors[cursor.sourceId] = cursor;
  }

  @override
  Future<bool> sourceForgotten(String sourceId) async =>
      _forgotten.contains(sourceId);

  @override
  Future<Set<String>> forgottenSources() async => Set<String>.from(_forgotten);

  @override
  Future<void> markForgotten(String sourceId) async {
    _forgotten.add(sourceId);
  }

  /// 反序列化时恢复遗忘集合（仅 [JsonRagBackend] 调用）。
  void restoreForgotten(Iterable<String> forgotten) {
    _forgotten.addAll(forgotten);
  }
}
