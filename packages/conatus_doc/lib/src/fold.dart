/// fold 引擎：把生效补丁集折叠成文档状态。
library;

import 'block.dart';
import 'doc_patch.dart';

/// 文档状态：补丁序列折叠后的派生视图（不独立存储）。
class DocumentState {
  /// 以有序块列表构造。
  const DocumentState(this.blocks);

  /// 有序块列表。
  final List<DocBlock> blocks;

  /// 全文（块间以换行相接）。
  String get text => blocks.map((DocBlock b) => b.text).join('\n');

  /// 块 [id] 是否存在。
  bool containsBlock(String id) => blocks.any((DocBlock b) => b.id == id);
}

/// 把 [patches] 按追加序折叠为文档状态。
///
/// 调用方传入的一般是 `PatchLog.effective(...)` 的生效集；失锚操作静默跳过。
DocumentState foldPatches(Iterable<DocPatch> patches) {
  final List<DocBlock> blocks = <DocBlock>[];
  for (final DocPatch patch in patches) {
    for (final op in patch.ops) {
      op.apply(blocks);
    }
  }
  return DocumentState(blocks);
}
