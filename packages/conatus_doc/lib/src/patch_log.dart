/// 补丁序列：只追加存储 + supersede 生效规则 + 作废标记。
library;

import 'annotation.dart';
import 'doc_patch.dart';

/// 补丁序列（故事层载体）。
///
/// 只追加是硬不变式：序列永不改写。「作废」与「supersede」都只影响
/// [effective] 的生效视图，不改历史——故事永不丢东西，状态完全可控。
class PatchLog {
  final List<DocPatch> _patches = <DocPatch>[];
  final List<DocAnnotation> _annotations = <DocAnnotation>[];
  final Set<String> _voided = <String>{};

  /// 全部补丁（追加序，含被 supersede / 作废的）。
  List<DocPatch> get patches => List<DocPatch>.unmodifiable(_patches);

  /// 全部锚点批注（追加序）。
  List<DocAnnotation> get annotations =>
      List<DocAnnotation>.unmodifiable(_annotations);

  /// 补丁数量。
  int get length => _patches.length;

  /// 追加补丁；[DocPatch.id] 重复时抛 [ArgumentError]。
  void append(DocPatch patch) {
    final bool duplicate = _patches.any((DocPatch p) => p.id == patch.id);
    if (duplicate) {
      throw ArgumentError.value(patch.id, 'patch.id', '补丁 id 重复');
    }
    _patches.add(patch);
  }

  /// 追加一条锚点批注。
  void annotate(DocAnnotation annotation) => _annotations.add(annotation);

  /// 作废补丁 [id]（截断与丢弃共用的标记）。
  void voidPatch(String id) => _voided.add(id);

  /// [id] 补丁是否已作废。
  bool voided(String id) => _voided.contains(id);

  /// 作废下标 [index] 之后的全部补丁（游标截断）。
  void truncateAfter(int index) {
    for (int i = index + 1; i < _patches.length; i++) {
      _voided.add(_patches[i].id);
    }
  }

  /// 截至 [upto]（不含，按追加序下标）生效的补丁集。
  ///
  /// 生效 = 未作废 + 未被另一个生效补丁 supersede。supersede 不追溯：
  /// 若 supersede 补丁在 [upto] 之后，旧补丁在 [upto] 处仍生效。
  List<DocPatch> effective({int? upto}) {
    final int end = upto ?? _patches.length;
    final List<DocPatch> window = _patches.sublist(0, end);
    final Set<String> superseded = <String>{
      for (final DocPatch p in window)
        if (p.supersedes != null && !_voided.contains(p.id)) p.supersedes!,
    };
    return <DocPatch>[
      for (final DocPatch p in window)
        if (!_voided.contains(p.id) && !superseded.contains(p.id)) p,
    ];
  }

  /// 分叉：复制 [upto]（不含）之前的完整前缀为一条新故事线。
  ///
  /// 前缀连作废标记一起复制，supersede 关系在新线上保持原样；旧线不受影响。
  PatchLog forkAt(int upto) {
    final PatchLog branch = PatchLog();
    for (final DocPatch p in _patches.sublist(0, upto)) {
      branch._patches.add(p);
      if (_voided.contains(p.id)) branch._voided.add(p.id);
    }
    branch._annotations.addAll(_annotations);
    return branch;
  }
}
