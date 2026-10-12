/// 补丁词汇：作者、可逆性类别与文档操作（op）。
library;

import 'block.dart';

/// 补丁作者：人或 AI（双写只有两个作者）。
enum PatchAuthor { human, ai }

/// 补丁的可逆性类别（回溯语义的依据，见设计文档 §4.2）。
enum PatchReversibility {
  /// 纯文档内部：恢复快照，零成本。
  documentInternal,

  /// 可再生的衍生物：标记失效，用到时重新生成。
  regenerable,

  /// 外部可补偿：不能撤回，只能补偿（Saga）。
  compensable,

  /// 单向门：物理不可逆，回溯到此为止。
  oneWayDoor,
}

/// 文档操作：对块序列的一次原子改动。
///
/// 每个 op 自己实现 [apply]（多态分发），失锚（目标块不存在）时静默跳过——
/// 失锚的呈现交给 dependency 层，fold 不猜。
sealed class PatchOp {
  const PatchOp();

  /// 本操作触及的块 id。
  String get blockId;

  /// 把操作应用到 [blocks]。
  void apply(List<DocBlock> blocks);

  /// 序列化为 JSON（含 `kind` 判别字段）。
  Map<String, Object?> toJson();
}

/// 在 [afterId] 块之后插入新块（`afterId` 为空或失锚时插到开头）。
class InsertBlockOp extends PatchOp {
  /// 以新块 [blockId] / [text] 与插入位置 [afterId] 构造。
  const InsertBlockOp({
    required this.blockId,
    required this.text,
    this.afterId,
  });

  @override
  final String blockId;

  /// 新块文本。
  final String text;

  /// 插入到该块之后；为空表示文档开头。
  final String? afterId;

  @override
  void apply(List<DocBlock> blocks) {
    final int at = afterId == null ? 0 : indexOfBlock(blocks, afterId!) + 1;
    blocks.insert(at, DocBlock(id: blockId, text: text));
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'kind': 'insert',
        'blockId': blockId,
        'text': text,
        if (afterId != null) 'afterId': afterId,
      };

  /// 从 JSON 反序列化。
  factory InsertBlockOp.fromJson(Map<String, Object?> json) => InsertBlockOp(
        blockId: json['blockId'] as String,
        text: json['text'] as String? ?? '',
        afterId: json['afterId'] as String?,
      );
}

/// 替换块文本（失锚时跳过）。
class ReplaceBlockOp extends PatchOp {
  /// 以目标 [blockId] 与新 [text] 构造。
  const ReplaceBlockOp({required this.blockId, required this.text});

  @override
  final String blockId;

  /// 替换后的文本。
  final String text;

  @override
  void apply(List<DocBlock> blocks) {
    final int at = indexOfBlock(blocks, blockId);
    if (at < 0) return;
    blocks[at] = blocks[at].copyWith(text: text);
  }

  @override
  Map<String, Object?> toJson() =>
      <String, Object?>{'kind': 'replace', 'blockId': blockId, 'text': text};

  /// 从 JSON 反序列化。
  factory ReplaceBlockOp.fromJson(Map<String, Object?> json) => ReplaceBlockOp(
        blockId: json['blockId'] as String,
        text: json['text'] as String? ?? '',
      );
}

/// 删除块（失锚时跳过）。
class RemoveBlockOp extends PatchOp {
  /// 以目标 [blockId] 构造。
  const RemoveBlockOp({required this.blockId});

  @override
  final String blockId;

  @override
  void apply(List<DocBlock> blocks) =>
      blocks.removeWhere((DocBlock b) => b.id == blockId);

  @override
  Map<String, Object?> toJson() =>
      <String, Object?>{'kind': 'remove', 'blockId': blockId};

  /// 从 JSON 反序列化。
  factory RemoveBlockOp.fromJson(Map<String, Object?> json) =>
      RemoveBlockOp(blockId: json['blockId'] as String);
}

/// 把块移动到 [afterId] 之后（`afterId` 为空移到开头；失锚时跳过）。
class MoveBlockOp extends PatchOp {
  /// 以目标 [blockId] 与落点 [afterId] 构造。
  const MoveBlockOp({required this.blockId, this.afterId});

  @override
  final String blockId;

  /// 移动到该块之后；为空表示文档开头。
  final String? afterId;

  @override
  void apply(List<DocBlock> blocks) {
    final int from = indexOfBlock(blocks, blockId);
    if (from < 0) return;
    final DocBlock moved = blocks.removeAt(from);
    final int at = afterId == null ? 0 : indexOfBlock(blocks, afterId!) + 1;
    blocks.insert(at, moved);
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'kind': 'move',
        'blockId': blockId,
        if (afterId != null) 'afterId': afterId,
      };

  /// 从 JSON 反序列化。
  factory MoveBlockOp.fromJson(Map<String, Object?> json) => MoveBlockOp(
        blockId: json['blockId'] as String,
        afterId: json['afterId'] as String?,
      );
}

/// 块 [id] 在 [blocks] 中的下标；不存在返回 -1。
int indexOfBlock(List<DocBlock> blocks, String id) {
  for (final (int index, DocBlock block) in blocks.indexed) {
    if (block.id == id) return index;
  }
  return -1;
}

/// 从 JSON 还原 op；未知 `kind` 抛 [ArgumentError]。
PatchOp patchOpFromJson(Map<String, Object?> json) {
  final PatchOp Function(Map<String, Object?>)? parser =
      _opParsers[json['kind']];
  if (parser == null) {
    throw ArgumentError.value(json['kind'], 'kind', '未知补丁操作');
  }
  return parser(json);
}

const Map<String, PatchOp Function(Map<String, Object?>)> _opParsers =
    <String, PatchOp Function(Map<String, Object?>)>{
  'insert': InsertBlockOp.fromJson,
  'replace': ReplaceBlockOp.fromJson,
  'remove': RemoveBlockOp.fromJson,
  'move': MoveBlockOp.fromJson,
};
