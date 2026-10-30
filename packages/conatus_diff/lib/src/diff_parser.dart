/// 统一格式 diff 的解析与内存行差异（`/diff` 数据层）。
///
/// 解析容忍 git 的扩展头（`diff --git` / `new file mode` / `rename from` /
/// `Binary files … differ`）与 `\ No newline at end of file`；目标路径统一去掉
/// `a/` / `b/` 前缀并还原 git 的引号转义。二进制（NUL 或 git 二进制标记）
/// 只留文件级结论。
library;

import 'diff_builder.dart';
import 'diff_model.dart';
import 'diff_types.dart';
import 'line_ops.dart';
import 'unified_diff.dart' as unified;

/// 解析统一格式 diff 文本，返回文件级变更（按出现顺序）。
///
/// 解析不出任何文件时返回空列表。
List<FileDiff> parseUnifiedDiff(String text) {
  final UnifiedDiffBuilder builder = UnifiedDiffBuilder();
  for (final String line in text.split('\n')) {
    builder.add(line);
  }
  return builder.finish();
}

/// 内存中两侧文本的行差异；内容相同返回空列表。
///
/// 任一侧行数超过 [maxLines] 或内容含 NUL 时只返回文件级结论（无 hunk，
/// 增删计数为 0）。[before] 为 `null` 表示新增文件，[after] 为 `null`
/// 表示删除文件。只有末尾换行的变化也算修改（否则会被误报为无变化）。
List<FileDiff> diffLines(
  String path,
  String? before,
  String? after, {
  int maxLines = 5000,
}) {
  if (before == after) return const <FileDiff>[];
  final String status = _statusFor(before, after);
  final _Sides sides = _Sides(before ?? '', after ?? '');
  final FileDiff? degraded = _degraded(path, status, sides, maxLines);
  if (degraded != null) return <FileDiff>[degraded];
  if (_sameLines(sides.oldLines, sides.newLines)) {
    return <FileDiff>[_file(path, status)];
  }
  final String patch = unified.buildUnifiedDiff(
    oldText: sides.oldText,
    newText: sides.newText,
    path: path,
    lcsLimit: maxLines,
  );
  if (patch.isNotEmpty) {
    final bool coarse = lineDiffCoarse(
      sides.oldLines,
      sides.newLines,
      maxLines,
    );
    return <FileDiff>[
      for (final FileDiff diff in parseUnifiedDiff(patch))
        FileDiff(
          path: diff.path,
          status: status,
          hunks: diff.hunks,
          additions: diff.additions,
          deletions: diff.deletions,
          coarse: coarse,
        ),
    ];
  }
  // 空文件的新增 / 删除没有 hunk，但仍是一条文件级变化。
  return before == null || after == null
      ? <FileDiff>[_file(path, status)]
      : const <FileDiff>[];
}

String _statusFor(String? before, String? after) {
  if (before == null) return 'added';
  if (after == null) return 'deleted';
  return 'modified';
}

bool _sameLines(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (int index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

/// 二进制 / 超长文件只给文件级结论；正常大小返回 `null` 交给行级 diff。
FileDiff? _degraded(String path, String status, _Sides sides, int maxLines) {
  if (sides.oldText.contains('\u0000') || sides.newText.contains('\u0000')) {
    return _file(path, 'binary');
  }
  if (sides.oldLines.length <= maxLines && sides.newLines.length <= maxLines) {
    return null;
  }
  return _file(path, status, truncated: true);
}

/// 文件级条目（无 hunk）；超限 / 二进制时增删计数为 0，不编造统计。
FileDiff _file(String path, String status, {bool truncated = false}) =>
    FileDiff(
      path: path,
      status: status,
      hunks: const <DiffHunk>[],
      truncated: truncated,
    );

/// 两侧文本的切行结果（只算一次，供降级判定与 LCS 共用）。
class _Sides {
  _Sides(this.oldText, this.newText)
      : oldLines = unified.splitLines(oldText),
        newLines = unified.splitLines(newText);

  final String oldText;
  final String newText;
  final List<String> oldLines;
  final List<String> newLines;
}
