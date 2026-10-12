/// 文档补丁：一组操作 + 作者 / 可逆性 / 依赖集 / supersede 指针。
library;

import 'patch.dart';

/// 文档补丁：人机双写的一等公民。
///
/// 补丁只追加不改写；「修改补丁」= 追加一个 [supersedes] 指向它的新补丁，
/// fold 时后者生效（见设计文档 §4.4）。
class DocPatch {
  /// 以稳定 [id]、[author] 与操作集 [ops] 构造。
  const DocPatch({
    required this.id,
    required this.author,
    required this.ops,
    this.reversibility = PatchReversibility.documentInternal,
    this.deps = const <String>{},
    this.supersedes,
  });

  /// 补丁唯一 id。
  final String id;

  /// 作者（人或 AI）。
  final PatchAuthor author;

  /// 本补丁的文档操作。
  final List<PatchOp> ops;

  /// 可逆性类别。
  final PatchReversibility reversibility;

  /// 前置依赖的补丁 id 集（显式声明；隐式块依赖由 dependency 层推导）。
  final Set<String> deps;

  /// 本补丁 supersede 的目标补丁 id。
  final String? supersedes;

  /// 复制并替换操作集 / 依赖集（按块收缩、重新锚定用）。
  DocPatch copyWith({List<PatchOp>? ops, Set<String>? deps}) => DocPatch(
        id: id,
        author: author,
        ops: ops ?? this.ops,
        reversibility: reversibility,
        deps: deps ?? this.deps,
        supersedes: supersedes,
      );

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'author': author.name,
        'ops': <Map<String, Object?>>[
          for (final PatchOp op in ops) op.toJson()
        ],
        'reversibility': reversibility.name,
        if (deps.isNotEmpty) 'deps': deps.toList(),
        if (supersedes != null) 'supersede': supersedes,
      };

  /// 从 JSON 反序列化。
  factory DocPatch.fromJson(Map<String, Object?> json) => DocPatch(
        id: json['id'] as String,
        author: PatchAuthor.values.byName(json['author'] as String? ?? 'ai'),
        ops: <PatchOp>[
          for (final Object? op in json['ops'] as List? ?? const <Object?>[])
            patchOpFromJson(Map<String, Object?>.from(op! as Map)),
        ],
        reversibility: PatchReversibility.values.byName(
          json['reversibility'] as String? ?? 'documentInternal',
        ),
        deps: <String>{
          for (final Object? dep in json['deps'] as List? ?? const <Object?>[])
            dep! as String,
        },
        supersedes: json['supersede'] as String?,
      );
}
