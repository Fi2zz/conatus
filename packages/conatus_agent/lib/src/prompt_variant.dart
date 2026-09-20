/// prompt-evolver 的类型词汇：提示词变体。
library;

/// 提示词变体。
///
/// 一段针对特定 prompt section 的候选文本，附带生成理由、演化链上的
/// 父变体与评估得分。未评估时 [score] 为 `null`。
class PromptVariant {
  const PromptVariant({
    required this.id,
    required this.sectionName,
    required this.text,
    required this.reason,
    required this.createdAt,
    this.parentId,
    this.score,
  });

  /// 从 JSON 反序列化。
  factory PromptVariant.fromJson(Map<String, Object?> json) => PromptVariant(
        id: '${json['id'] ?? ''}',
        sectionName: '${json['sectionName'] ?? ''}',
        text: '${json['text'] ?? ''}',
        reason: '${json['reason'] ?? ''}',
        createdAt:
            DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime.now(),
        parentId: json['parentId'] as String?,
        score: (json['score'] as num?)?.toDouble(),
      );

  /// 变体唯一 ID。
  final String id;

  /// 目标 section 名。
  final String sectionName;

  /// 变体文本。
  final String text;

  /// 生成理由（通常为失败模式分析结果）。
  final String reason;

  /// 父变体 ID。用于追踪演化链。
  final String? parentId;

  /// 评估得分。未评估时为 `null`。
  final double? score;

  /// 创建时间。
  final DateTime createdAt;

  /// 复制并替换得分；传 `null` 清除。
  PromptVariant copyWith({double? score}) => PromptVariant(
        id: id,
        sectionName: sectionName,
        text: text,
        reason: reason,
        createdAt: createdAt,
        parentId: parentId,
        score: score,
      );

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'sectionName': sectionName,
        'text': text,
        'reason': reason,
        'createdAt': createdAt.toIso8601String(),
        if (parentId != null) 'parentId': parentId,
        if (score != null) 'score': score,
      };

  @override
  String toString() => 'PromptVariant($id, $sectionName)';
}
