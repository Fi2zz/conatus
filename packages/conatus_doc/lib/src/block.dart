/// 文档块：补丁锚定的最小单元。
library;

/// 文档块：以稳定 [id] 标识。
///
/// 补丁与批注一律锚定块 id，绝不锚偏移量——前面插入内容不影响后续块的锚。
class DocBlock {
  /// 以稳定 [id] 与当前 [text] 构造。
  const DocBlock({required this.id, required this.text});

  /// 稳定块 id（创建时分配，永不复用）。
  final String id;

  /// 块的当前文本。
  final String text;

  /// 复制并替换文本。
  DocBlock copyWith({String? text}) =>
      DocBlock(id: id, text: text ?? this.text);

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'text': text};

  /// 从 JSON 反序列化。
  factory DocBlock.fromJson(Map<String, Object?> json) => DocBlock(
        id: json['id'] as String,
        text: json['text'] as String? ?? '',
      );
}
