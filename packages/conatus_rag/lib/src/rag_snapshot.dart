import 'rag_chunk.dart';

/// 来源的摄入游标，属于来源并带租户，便于清理。
class RagCursor {
  const RagCursor({
    required this.tenantId,
    required this.sourceId,
    required this.lastSeq,
  });

  final String tenantId;
  final String sourceId;
  final int lastSeq;

  Map<String, Object?> toJson() => <String, Object?>{
        'tenantId': tenantId,
        'sourceId': sourceId,
        'lastSeq': lastSeq,
      };

  factory RagCursor.fromJson(Map<String, Object?> json) => RagCursor(
        tenantId: json['tenantId']! as String,
        sourceId: json['sourceId']! as String,
        lastSeq: json['lastSeq']! as int,
      );
}

/// 索引版本元信息。嵌入模型、维度或切片版本变化时必须重建。
class RagSnapshotMeta {
  const RagSnapshotMeta({
    required this.embeddingModel,
    required this.dimension,
    required this.indexVersion,
    this.updatedAt,
  });

  final String embeddingModel;
  final int dimension;
  final int indexVersion;
  final DateTime? updatedAt;

  /// 只比较模型、维度与索引版本，忽略更新时间。
  bool matches(RagSnapshotMeta expected) =>
      embeddingModel == expected.embeddingModel &&
      dimension == expected.dimension &&
      indexVersion == expected.indexVersion;
}

/// 索引的完整快照：切片、与之一一对应的向量、以及各来源游标。
class RagSnapshot {
  const RagSnapshot({
    required this.meta,
    required this.chunks,
    required this.vectors,
    required this.cursors,
  });

  final RagSnapshotMeta meta;
  final List<RagChunk> chunks;
  final List<List<double>> vectors;
  final List<RagCursor> cursors;
}
