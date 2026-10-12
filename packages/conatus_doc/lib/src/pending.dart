/// 待定补丁的按块收缩：「编辑即裁剪」（设计文档 §3）。
library;

import 'doc_patch.dart';
import 'patch.dart';

/// 待定补丁被人直接编辑后的拆分结果。
class PendingSplit {
  /// [aiRemainder] 为 null 表示 AI 补丁被改空（无需再接受）。
  const PendingSplit({required this.humanPatch, this.aiRemainder});

  /// 收缩后的 AI 补丁（人碰过的块已脱离）。
  final DocPatch? aiRemainder;

  /// 人的改动独立成的补丁。
  final DocPatch humanPatch;
}

/// 拆分待定补丁：[humanOps] 触及的块从 [pending] 脱离，余下部分仍可
/// 整体接受 / 拒绝。
///
/// 人改的是 AI 待定**新建**的块时，人的补丁直接携带建块 op（含人的文本），
/// 否则建块 op 被裁剪后人补丁会失锚。余下 ops 里落点（afterId）锚在被带走
/// 块上的，传递改锚到该块自己的落点。拆分后的两个补丁各自自足，互不依赖。
PendingSplit splitPending(
  DocPatch pending,
  List<PatchOp> humanOps,
  String humanPatchId,
) {
  final Set<String> touched = <String>{
    for (final PatchOp o in humanOps) o.blockId,
  };
  final Map<String, String?> carried = <String, String?>{
    for (final PatchOp o in pending.ops)
      if (o is InsertBlockOp && touched.contains(o.blockId))
        o.blockId: o.afterId,
  };
  final List<PatchOp> remaining = <PatchOp>[
    for (final PatchOp o in pending.ops)
      if (!touched.contains(o.blockId)) _reanchor(o, carried),
  ];
  final DocPatch humanPatch = DocPatch(
    id: humanPatchId,
    author: PatchAuthor.human,
    ops: <PatchOp>[
      for (final PatchOp o in humanOps) _carryCreation(o, pending)
    ],
  );
  if (remaining.isEmpty) return PendingSplit(humanPatch: humanPatch);
  return PendingSplit(
    humanPatch: humanPatch,
    aiRemainder: pending.copyWith(ops: remaining),
  );
}

/// 落点块被带走的 op 改锚到该块自己的落点（传递解析）。
PatchOp _reanchor(PatchOp op, Map<String, String?> carried) {
  final String? anchor = _resolveAnchor(_anchorOf(op), carried);
  if (anchor == _anchorOf(op)) return op;
  return _withAnchor(op, anchor);
}

String? _anchorOf(PatchOp op) {
  if (op is InsertBlockOp) return op.afterId;
  if (op is MoveBlockOp) return op.afterId;
  return null;
}

PatchOp _withAnchor(PatchOp op, String? afterId) {
  if (op is InsertBlockOp) {
    return InsertBlockOp(
      blockId: op.blockId,
      text: op.text,
      afterId: afterId,
    );
  }
  if (op is MoveBlockOp) {
    return MoveBlockOp(blockId: op.blockId, afterId: afterId);
  }
  return op;
}

String? _resolveAnchor(String? anchor, Map<String, String?> carried) {
  String? current = anchor;
  while (current != null && carried.containsKey(current)) {
    current = carried[current];
  }
  return current;
}

/// 人改的块若是 [pending] 新建的，把建块 op 并进人补丁（文本取人的）。
PatchOp _carryCreation(PatchOp humanOp, DocPatch pending) {
  if (humanOp is! ReplaceBlockOp) return humanOp;
  for (final PatchOp op in pending.ops) {
    if (op is InsertBlockOp && op.blockId == humanOp.blockId) {
      return InsertBlockOp(
        blockId: op.blockId,
        text: humanOp.text,
        afterId: op.afterId,
      );
    }
  }
  return humanOp;
}
