/// 一次调用或一个会话的归属与可见范围。由宿主从身份与会话表解析后传入。
class RagScope {
  RagScope({
    required String tenantId,
    this.principalId,
    Set<String> visibilityTags = const <String>{},
  })  : tenantId = _requireTenant(tenantId),
        visibilityTags = Set<String>.unmodifiable(<String>{
          ...visibilityTags,
          'tenant:$tenantId',
        });

  final String tenantId;

  /// 用户或服务身份；缺省时只按租户与标签过滤。
  final String? principalId;

  /// 主体可见标签；构造后必含 `tenant:<tenantId>`。
  final Set<String> visibilityTags;

  static String _requireTenant(String tenantId) {
    if (tenantId.trim().isEmpty) {
      throw ArgumentError.value(tenantId, 'tenantId', '租户标识不能为空');
    }
    return tenantId;
  }
}

/// 一次摄入的来源与归属。
class RagSource {
  const RagSource({
    required this.sourceKind,
    required this.sourceId,
    required this.scope,
  });

  /// v1 固定为 `session`。
  final String sourceKind;

  /// v1 为 sessionId。
  final String sourceId;

  final RagScope scope;
}

/// 切片参数，按字符近似 token。
class ChunkerConfig {
  const ChunkerConfig({
    required this.chunkChars,
    required this.overlapChars,
    required this.maxChunkChars,
  });

  final int chunkChars;
  final int overlapChars;

  /// 单块上限，防止单个超长事件撑爆上下文。
  final int maxChunkChars;
}
