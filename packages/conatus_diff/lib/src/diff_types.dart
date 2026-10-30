/// diff 的公共类型：行编辑操作、文件块、hunk。
library;

/// 行级编辑操作的类型。
enum DiffOpKind { equal, delete, insert }

/// 一行编辑操作。
class DiffOp {
  const DiffOp(this.kind, this.text);

  final DiffOpKind kind;

  /// 行内容（不含前缀符）。
  final String text;
}

/// 一个文件的差异（路径 + hunk 列表）。
class DiffFile {
  const DiffFile({required this.path, required this.hunks});

  /// 目标文件路径（相对工作目录）。
  final String path;

  final List<DiffHunk> hunks;
}

/// 一个 hunk：`@@ -a,b +c,d @@` 与其内容行。
class DiffHunk {
  const DiffHunk({
    required this.oldStart,
    required this.oldLines,
    required this.newStart,
    required this.newLines,
    required this.lines,
  });

  /// 旧文件起始行（1 起）。
  final int oldStart;

  /// 旧文件覆盖行数。
  final int oldLines;

  /// 新文件起始行（1 起）。
  final int newStart;

  /// 新文件覆盖行数。
  final int newLines;

  /// hunk 内容行：每行以 `' '`、`'-'` 或 `'+'` 开头。
  final List<String> lines;
}
