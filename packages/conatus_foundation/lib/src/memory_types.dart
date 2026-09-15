/// memory 插件的类型词汇：一条长记忆。
library;

/// 一条长记忆：自由文本 + 标签 + 创建时间。
class MemoryEntry {
  const MemoryEntry({
    required this.id,
    required this.text,
    this.tags = const <String>{},
    required this.createdAt,
  });

  /// 从 JSON 反序列化。
  factory MemoryEntry.fromJson(Map<String, Object?> json) => MemoryEntry(
        id: json['id'] as String? ?? '',
        text: json['text'] as String? ?? '',
        tags: <String>{
          for (final Object? tag
              in (json['tags'] as List<Object?>?) ?? const <Object?>[])
            '$tag',
        },
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );

  /// 记忆标识。
  final String id;

  /// 记忆正文。
  final String text;

  /// 标签（参与召回打分）。
  final Set<String> tags;

  /// 创建时间。
  final DateTime createdAt;

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'text': text,
        if (tags.isNotEmpty) 'tags': tags.toList(growable: false),
        'createdAt': createdAt.toIso8601String(),
      };

  @override
  String toString() => 'MemoryEntry($id)';
}
