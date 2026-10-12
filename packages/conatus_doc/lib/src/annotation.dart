/// 锚点批注：锚在块 id 上的轻量提问（带位置的 ask_user）。
library;

import 'fold.dart';
import 'patch.dart';

/// 锚点批注：锚定 [blockId] 的一段批注 / 提问。
///
/// 批注是补丁家族的一员：只追加、有作者、可失锚。锚定的块消失时批注
/// 成为「悬浮批注」，由 [floatingAnnotations] 检出，交人重新锚定或丢弃。
class DocAnnotation {
  /// 以稳定 [id]、锚点 [blockId]、[author] 与 [text] 构造。
  const DocAnnotation({
    required this.id,
    required this.blockId,
    required this.author,
    required this.text,
  });

  /// 批注唯一 id。
  final String id;

  /// 锚定的块 id。
  final String blockId;

  /// 作者（人或 AI）。
  final PatchAuthor author;

  /// 批注内容。
  final String text;

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'blockId': blockId,
        'author': author.name,
        'text': text,
      };

  /// 从 JSON 反序列化。
  factory DocAnnotation.fromJson(Map<String, Object?> json) => DocAnnotation(
        id: json['id'] as String,
        blockId: json['blockId'] as String,
        author: PatchAuthor.values.byName(json['author'] as String? ?? 'human'),
        text: json['text'] as String? ?? '',
      );
}

/// 检出悬浮批注：锚定块已不在 [state] 里的批注。
List<DocAnnotation> floatingAnnotations(
  List<DocAnnotation> annotations,
  DocumentState state,
) {
  final Set<String> alive = <String>{for (final b in state.blocks) b.id};
  return <DocAnnotation>[
    for (final DocAnnotation a in annotations)
      if (!alive.contains(a.blockId)) a,
  ];
}
