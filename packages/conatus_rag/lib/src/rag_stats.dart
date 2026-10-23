/// 运行统计，只含计数与时间，不含查询原文或证据正文。
class RagStats {
  const RagStats({
    required this.chunks,
    required this.retrievals,
    required this.emptyResults,
    required this.rerankFallbacks,
    required this.embedFailures,
    this.lastIngestAt,
  });

  factory RagStats.zero() => const RagStats(
        chunks: 0,
        retrievals: 0,
        emptyResults: 0,
        rerankFallbacks: 0,
        embedFailures: 0,
      );

  final int chunks;
  final int retrievals;
  final int emptyResults;
  final int rerankFallbacks;
  final int embedFailures;
  final DateTime? lastIngestAt;
}

/// 带稳定错误码的 RAG 异常。消息不得包含查询原文或凭据。
class RagException implements Exception {
  const RagException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'RagException($code): $message';
}
