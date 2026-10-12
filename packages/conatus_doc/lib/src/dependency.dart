/// 补丁依赖图：显式 deps ∪ 隐式块依赖，支撑失锚级联（设计文档 §4.5）。
library;

import 'doc_patch.dart';
import 'patch.dart';

/// 补丁依赖索引：从补丁序列构建，回答「谁依赖谁」。
///
/// 隐式依赖：补丁 B 的操作触及补丁 A 创建的块，则 B 依赖 A——与 Pijul 的
/// 依赖理论同构。回滚 / supersede A 时用 [collectOrphaned] 级联找出失锚者，
/// 交人重新锚定、改写或丢弃，不自动猜。
class DependencyIndex {
  DependencyIndex._(this._deps);

  final Map<String, Set<String>> _deps;

  /// 从 [patches]（一般取 `PatchLog.effective()`）构建索引。
  factory DependencyIndex.fromPatches(List<DocPatch> patches) {
    final Map<String, String> creators = <String, String>{};
    final Map<String, Set<String>> deps = <String, Set<String>>{};
    for (final DocPatch p in patches) {
      deps[p.id] = <String>{...p.deps, ..._implicitDeps(p, creators)};
      _registerCreators(p, creators);
    }
    return DependencyIndex._(deps);
  }

  /// [patchId] 的全部前置依赖（显式 ∪ 隐式）；未知 id 返回空集。
  Set<String> depsOf(String patchId) =>
      Set<String>.unmodifiable(_deps[patchId] ?? const <String>{});

  /// 级联失锚：依赖（含传递依赖）[removedId] 的补丁 id 集。
  Set<String> collectOrphaned(String removedId) {
    final Set<String> orphaned = <String>{removedId};
    bool grew = true;
    while (grew) {
      grew = false;
      for (final MapEntry<String, Set<String>> entry in _deps.entries) {
        final bool dependent = entry.value.any(orphaned.contains);
        if (dependent && orphaned.add(entry.key)) grew = true;
      }
    }
    return orphaned..remove(removedId);
  }

  static Set<String> _implicitDeps(
    DocPatch patch,
    Map<String, String> creators,
  ) =>
      <String>{
        for (final PatchOp op in patch.ops)
          if (creators.containsKey(op.blockId)) creators[op.blockId]!,
      };

  static void _registerCreators(DocPatch patch, Map<String, String> creators) {
    for (final PatchOp op in patch.ops) {
      if (op is InsertBlockOp) creators[op.blockId] = patch.id;
    }
  }
}
