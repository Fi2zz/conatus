import 'rag_chunk.dart';
import 'rag_query.dart';
import 'rag_snapshot.dart';

export 'in_memory_backend.dart';

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

  /// 删除匹配切片，清掉匹配来源的游标，并把其来源记入遗忘集合，
  /// 避免懒补齐重新摄入（[RagIndexer.rebuild] 保留、[clear] 清空遗忘集合）。
  Future<int> delete(RagFilter filter);

  Future<int> count();

  /// 清空切片、向量、游标、遗忘集合与 meta（显式全量清除）。
  Future<void> clear();

  Future<RagCursor?> cursorOf(String sourceId);

  Future<void> saveCursor(RagCursor cursor);

  /// 该来源是否已被遗忘。
  Future<bool> sourceForgotten(String sourceId);

  /// 返回被遗忘来源 id 集合；[RagIndexer.rebuild] 前捕获以便恢复。
  Future<Set<String>> forgottenSources();

  /// 标记来源为遗忘（幂等）。
  Future<void> markForgotten(String sourceId);
}

/// 切片是否对过滤条件可见：租户相等、标签交集、来源白名单、时间窗相交。
bool chunkMatches(RagChunk chunk, RagFilter filter) =>
    chunk.tenantId == filter.tenantId &&
    _matchesTags(chunk, filter) &&
    _matchesScope(chunk, filter);

bool _matchesScope(RagChunk chunk, RagFilter filter) =>
    _matchesSources(chunk, filter.sourceIds) &&
    _overlapsWindow(chunk, filter.from, filter.to);

bool _matchesSources(RagChunk chunk, Set<String>? sourceIds) =>
    sourceIds == null || sourceIds.contains(chunk.sourceId);

/// 标签下推：只比较剔除 `tenant:` 后的额外标签，租户级块按 [RagFilter.includeTenantWide]
/// 放行；`anyTags` 为空集时拒绝一切带额外标签的块（fail closed）。
bool _matchesTags(RagChunk chunk, RagFilter filter) {
  final Set<String>? anyTags = filter.anyTags;
  if (anyTags == null) return true;
  final Set<String> extra = chunk.visibilityTags
      .where((String tag) => !tag.startsWith('tenant:'))
      .toSet();
  if (extra.isEmpty) return filter.includeTenantWide;
  return extra.any(anyTags.contains);
}

bool _overlapsWindow(RagChunk chunk, DateTime? from, DateTime? to) {
  if (from != null && chunk.endTime.isBefore(from)) {
    return false;
  }
  return to == null || !chunk.startTime.isAfter(to);
}
