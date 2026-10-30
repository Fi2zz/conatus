/// `/diff` 的数据模型：范围枚举与带统计的文件级差异。
library;

import 'diff_types.dart';

/// diff 的比较范围。
enum DiffScope {
  /// 工作区相对索引的改动（含未跟踪文件）。
  working,

  /// 检查点在某一轮相对上一轮的改动。
  turn,
}

/// 一个文件的差异：路径、状态、hunk 与增删行数。
///
/// 继承 [DiffFile]，因此可直接喂给 `applyDiffFile` 等既有纯函数；比父类多出
/// 状态词、统计与截断标记，供 `/diff` 视图直接渲染。
class FileDiff extends DiffFile {
  const FileDiff({
    required super.path,
    required this.status,
    required super.hunks,
    this.additions = 0,
    this.deletions = 0,
    this.truncated = false,
    this.coarse = false,
  });

  /// `added` / `modified` / `deleted` / `renamed` / `binary`。
  final String status;

  /// 新增行数。
  final int additions;

  /// 删除行数。
  final int deletions;

  /// 文件过大、只给文件级结论（无 hunk）。
  final bool truncated;

  /// 行差异因 LCS 预算退化为整段删/增：内容完整但**非最小** hunk，
  /// 增删计数是整段的，不是精确编辑数。
  final bool coarse;

  /// 复制并替换状态词；把 checkpoint 的状态（如 `renamed`）盖到内容比对
  /// 得出的状态上。
  FileDiff copyWith({String? status}) => FileDiff(
        path: path,
        status: status ?? this.status,
        hunks: hunks,
        additions: additions,
        deletions: deletions,
        truncated: truncated,
        coarse: coarse,
      );
}
