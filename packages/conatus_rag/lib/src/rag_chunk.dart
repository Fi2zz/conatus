/// 可引用的原文证据位置。
class Citation {
  const Citation({
    required this.sourceKind,
    required this.sourceId,
    required this.startTime,
    required this.endTime,
    this.url,
    this.firstSeq,
    this.lastSeq,
  });

  final String sourceKind;
  final String sourceId;

  /// 文档接入后填写；会话来源为 null。
  final String? url;
  final int? firstSeq;
  final int? lastSeq;
  final DateTime startTime;
  final DateTime endTime;
}

/// 索引中的一个原文切片。`text` 永不改写，直接作为证据。
class RagChunk {
  RagChunk({
    required this.id,
    required this.tenantId,
    required this.sourceKind,
    required this.sourceId,
    required this.eventIds,
    required this.startTime,
    required this.endTime,
    required this.text,
    this.visibilityTags = const <String>{},
    this.firstSeq,
    this.lastSeq,
  });

  /// `<sourceKind>/<sourceId>/<first>-<last>`，稳定幂等。
  final String id;
  final String tenantId;
  final String sourceKind;

  /// v1 为 sessionId。
  final String sourceId;
  final Set<String> visibilityTags;

  /// 会话专属的事件序号范围。
  final int? firstSeq;
  final int? lastSeq;
  final Set<String> eventIds;
  final DateTime startTime;
  final DateTime endTime;
  final String text;

  Citation get citation => Citation(
        sourceKind: sourceKind,
        sourceId: sourceId,
        firstSeq: firstSeq,
        lastSeq: lastSeq,
        startTime: startTime,
        endTime: endTime,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'tenantId': tenantId,
        'sourceKind': sourceKind,
        'sourceId': sourceId,
        'visibilityTags': visibilityTags.toList(),
        'firstSeq': firstSeq,
        'lastSeq': lastSeq,
        'eventIds': eventIds.toList(),
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'text': text,
      };

  factory RagChunk.fromJson(Map<String, Object?> json) => RagChunk(
        id: json['id']! as String,
        tenantId: json['tenantId']! as String,
        sourceKind: json['sourceKind']! as String,
        sourceId: json['sourceId']! as String,
        visibilityTags: _stringSet(json['visibilityTags']),
        firstSeq: json['firstSeq'] as int?,
        lastSeq: json['lastSeq'] as int?,
        eventIds: _stringSet(json['eventIds']),
        startTime: DateTime.parse(json['startTime']! as String),
        endTime: DateTime.parse(json['endTime']! as String),
        text: json['text']! as String,
      );

  static Set<String> _stringSet(Object? value) =>
      (value! as List<dynamic>).cast<String>().toSet();
}

/// 检索命中：切片加上余弦分与可选重排分。
class RagHit {
  const RagHit({
    required this.chunk,
    required this.score,
    this.rerankScore,
  });

  final RagChunk chunk;

  /// 余弦相似度。
  final double score;
  final double? rerankScore;

  Citation get citation => chunk.citation;
}

/// 估算文本 token 数：按 2 个字符 1 token 保守计，空串为 0。
int estimateTokens(String text) => (text.runes.length / 2).ceil();
