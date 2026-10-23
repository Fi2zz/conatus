import 'rag_scope.dart';

/// 检索请求。`limit` 与 `tokenBudget` 缺省分别为 15 与 2000。
class RetrievalRequest {
  const RetrievalRequest({
    required this.query,
    required this.scope,
    this.limit = 15,
    this.tokenBudget = 2000,
    this.sourceIds,
    this.from,
    this.to,
  });

  final String query;
  final RagScope scope;
  final int limit;
  final int tokenBudget;
  final Set<String>? sourceIds;
  final DateTime? from;
  final DateTime? to;
}

/// 由可见性策略生成、下推给后端的过滤条件。
class RagFilter {
  const RagFilter({
    required this.tenantId,
    this.anyTags,
    this.sourceIds,
    this.from,
    this.to,
    this.includeTenantWide = false,
  });

  final String tenantId;

  /// 与切片的 `visibilityTags` 求交（剔除 `tenant:` 标签后），空集即无匹配。
  final Set<String>? anyTags;
  final Set<String>? sourceIds;
  final DateTime? from;
  final DateTime? to;

  /// 租户级块（无额外标签）是否可见；缺省 false，删除等场景只按显式标签匹配。
  final bool includeTenantWide;
}
