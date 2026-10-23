import 'rag_chunk.dart';
import 'rag_query.dart';
import 'rag_scope.dart';

/// 可见性策略：决定切片对某作用域是否可见。
abstract interface class VisibilityPolicy {
  /// 为给定作用域构造过滤条件。
  RagFilter filterFor(RagScope scope);

  /// 判断切片对给定作用域是否可见。
  bool allows(RagChunk chunk, RagScope scope);
}

/// 基于租户与标签交集的可见性策略。
class TenantTagPolicy implements VisibilityPolicy {
  @override
  RagFilter filterFor(RagScope scope) =>
      RagFilter(tenantId: scope.tenantId, anyTags: scope.visibilityTags);

  @override
  bool allows(RagChunk chunk, RagScope scope) {
    if (chunk.tenantId != scope.tenantId) return false;

    final String tenantTag = 'tenant:${scope.tenantId}';
    final Set<String> scopeAdditionalTags =
        scope.visibilityTags.difference(<String>{tenantTag});
    final Set<String> chunkAdditionalTags =
        chunk.visibilityTags.difference(<String>{tenantTag});

    // Tenant-wide chunk (no additional tags) → visible to any scope in tenant
    if (chunkAdditionalTags.isEmpty) return true;
    // Scope with no additional tags → only sees tenant-wide chunks
    if (scopeAdditionalTags.isEmpty) return false;
    // Otherwise → check intersection
    return chunkAdditionalTags.any(scopeAdditionalTags.contains);
  }
}
