import 'cosine.dart';
import 'rag_chunk.dart';
import 'rag_query.dart';
import 'rag_snapshot.dart';
import 'rag_stats.dart';

/// 索引后端端口。内存与 JSON 实现只是参考，后续 pgvector 等实现同一契约。
abstract interface class RagIndexBackend {
  Future<RagSnapshotMeta?> meta();

  /// 模型、维度或索引版本不一致时抛 `rag_index_stale`，需先 [clear]。
  Future<void> init(RagSnapshotMeta meta);

  /// 先按 [filter] 过滤（租户、标签交集、来源白名单、时间窗），再按
  /// `queryVector · chunkVector` 的余弦分取前 [k]。同分按 chunk id 升序。
  /// 调用方负责把请求的 sourceIds/from/to 并入 [filter]。
  Future<List<RagHit>> search(
    RagFilter filter, {
    required List<double> queryVector,
    required int k,
  });

  /// 向量维度必须与索引内已有向量一致，否则抛 [ArgumentError]。
  Future<void> upsert(List<RagChunk> chunks, List<List<double>> vectors);

  /// 删除匹配切片，并清掉匹配来源的游标。
  Future<int> delete(RagFilter filter);

  Future<int> count();

  /// 清空切片、向量、游标与 meta。
  Future<void> clear();

  Future<RagCursor?> cursorOf(String sourceId);

  Future<void> saveCursor(RagCursor cursor);
}

/// 切片是否对过滤条件可见：租户相等、标签交集、来源白名单、时间窗相交。
bool chunkMatches(RagChunk chunk, RagFilter filter) =>
    chunk.tenantId == filter.tenantId &&
    _matchesTags(chunk, filter.anyTags) &&
    _matchesScope(chunk, filter);

bool _matchesScope(RagChunk chunk, RagFilter filter) =>
    _matchesSources(chunk, filter.sourceIds) &&
    _overlapsWindow(chunk, filter.from, filter.to);

bool _matchesSources(RagChunk chunk, Set<String>? sourceIds) =>
    sourceIds == null || sourceIds.contains(chunk.sourceId);

bool _matchesTags(RagChunk chunk, Set<String>? anyTags) =>
    anyTags == null || chunk.visibilityTags.any(anyTags.contains);

bool _overlapsWindow(RagChunk chunk, DateTime? from, DateTime? to) {
  if (from != null && chunk.endTime.isBefore(from)) {
    return false;
  }
  return to == null || !chunk.startTime.isAfter(to);
}

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
    for (final String id in ids) {
      _chunks.remove(id);
      _vectors.remove(id);
    }
    _cursors.removeWhere(
        (String _, RagCursor cursor) => _cursorMatches(cursor, filter));
    return ids.length;
  }

  @override
  Future<int> count() async => _chunks.length;

  @override
  Future<void> clear() async {
    _chunks.clear();
    _vectors.clear();
    _cursors.clear();
    _meta = null;
  }

  @override
  Future<RagCursor?> cursorOf(String sourceId) async => _cursors[sourceId];

  @override
  Future<void> saveCursor(RagCursor cursor) async {
    _cursors[cursor.sourceId] = cursor;
  }
}
