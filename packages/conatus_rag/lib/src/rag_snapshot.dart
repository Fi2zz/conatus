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

  Map<String, Object?> toJson() => <String, Object?>{
        'embeddingModel': embeddingModel,
        'dimension': dimension,
        'indexVersion': indexVersion,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory RagSnapshotMeta.fromJson(Map<String, Object?> json) {
    final String? updatedAt = json['updatedAt'] as String?;
    return RagSnapshotMeta(
      embeddingModel: json['embeddingModel']! as String,
      dimension: json['dimension']! as int,
      indexVersion: json['indexVersion']! as int,
      updatedAt: updatedAt == null ? null : DateTime.parse(updatedAt),
    );
  }
}

/// 索引的完整快照：切片、与之一一对应的向量、各来源游标，以及被遗忘的来源 id。
/// `meta` 为空表示尚未 init；此时切片仍可能已写入（与内存实现一致）。
class RagSnapshot {
  const RagSnapshot({
    required this.meta,
    required this.chunks,
    required this.vectors,
    required this.cursors,
    this.forgotten = const <String>{},
  });

  final RagSnapshotMeta? meta;
  final List<RagChunk> chunks;
  final List<List<double>> vectors;
  final List<RagCursor> cursors;

  /// 被遗忘的来源 id：forget 后不再被懒补齐重新摄入。
  final Set<String> forgotten;

  Map<String, Object?> toJson() => <String, Object?>{
        'meta': meta?.toJson(),
        'chunks': <Object?>[
          for (final RagChunk chunk in chunks) chunk.toJson()
        ],
        'vectors': vectors,
        'cursors': <Object?>[
          for (final RagCursor cursor in cursors) cursor.toJson(),
        ],
        'forgotten': forgotten.toList(),
      };

  factory RagSnapshot.fromJson(Map<String, Object?> json) {
    final Object? rawMeta = json['meta'];
    return RagSnapshot(
      meta: rawMeta == null
          ? null
          : RagSnapshotMeta.fromJson(rawMeta as Map<String, Object?>),
      chunks: <RagChunk>[
        for (final Object? item in json['chunks']! as List<Object?>)
          RagChunk.fromJson(item! as Map<String, Object?>),
      ],
      vectors: <List<double>>[
        for (final Object? vector in json['vectors']! as List<Object?>)
          <double>[
            for (final Object? value in vector! as List<Object?>)
              (value! as num).toDouble(),
          ],
      ],
      cursors: <RagCursor>[
        for (final Object? item in json['cursors']! as List<Object?>)
          RagCursor.fromJson(item! as Map<String, Object?>),
      ],
      forgotten: <String>{
        for (final Object? item
            in json['forgotten'] as List<Object?>? ?? const <Object?>[])
          item! as String,
      },
    );
  }
}
