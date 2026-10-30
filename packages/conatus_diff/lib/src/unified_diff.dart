/// 统一格式（unified）diff 的生成：按行 LCS，输出 `--- / +++` 头与 `@@` hunk。
library;

import 'diff_types.dart';
import 'line_ops.dart';

/// 参与 LCS 计算的单侧默认最大行数；超过则退化为整体替换。
///
/// `/diff` 的内存行差异会传入自己的 `maxLines`（默认 5000），两者阈值
/// 因此对齐；本常量只保留给其它调用方的默认行为。
const int kMaxDiffLines = 2000;

/// 生成统一格式 diff；两侧内容相同返回空串。
///
/// [path] 同时用于 `--- a/path` 与 `+++ b/path` 两个头。[lcsLimit] 是单侧
/// 行数上限，超过时中段退化为整体替换。
String buildUnifiedDiff({
  required String oldText,
  required String newText,
  required String path,
  int context = 3,
  int lcsLimit = kMaxDiffLines,
}) {
  final List<String> oldLines = splitLines(oldText);
  final List<String> newLines = splitLines(newText);
  final List<DiffOp> ops = diffLines(oldLines, newLines, lcsLimit: lcsLimit);
  final List<(int, int)> groups = _changeGroups(ops, context);
  if (groups.isEmpty) return '';
  final StringBuffer out = StringBuffer()
    ..writeln('--- a/$path')
    ..writeln('+++ b/$path');
  for (final (int start, int end) in groups) {
    _writeHunk(out, ops, start, end);
  }
  return out.toString();
}

/// 按 `\n` 切行；尾部换行不产生空行，空文本返回空列表。
List<String> splitLines(String text) {
  if (text.isEmpty) return const <String>[];
  final String body =
      text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
  return body.isEmpty ? const <String>[] : body.split('\n');
}

/// 行级差异：先裁公共前后缀，再对中段做 LCS（见 `line_ops.dart`）。
///
/// [lcsLimit] 是单侧行数上限；中段超限或矩阵超预算时整段删/增。
List<DiffOp> diffLines(
  List<String> a,
  List<String> b, {
  int lcsLimit = kMaxDiffLines,
}) =>
    lineDiffOps(a, b, lcsLimit);

/// 把变更行聚成 hunk 区间（含 [context] 行上下文，间隔不足 2×context 时合并）。
// REASON: 区间合并是既定算法逻辑，分支由边界条件决定。
List<(int, int)> _changeGroups(List<DiffOp> ops, int context) {
  final List<int> changeIdx = <int>[
    for (int i = 0; i < ops.length; i++)
      if (ops[i].kind != DiffOpKind.equal) i,
  ];
  if (changeIdx.isEmpty) return const <(int, int)>[];
  final List<(int, int)> groups = <(int, int)>[];
  int start = (changeIdx.first - context).clamp(0, ops.length);
  int prev = changeIdx.first;
  for (final int idx in changeIdx.skip(1)) {
    if (idx - prev > 2 * context) {
      groups.add((start, (prev + context + 1).clamp(0, ops.length)));
      start = (idx - context).clamp(0, ops.length);
    }
    prev = idx;
  }
  groups.add((start, (prev + context + 1).clamp(0, ops.length)));
  return groups;
}

void _writeHunk(StringBuffer out, List<DiffOp> ops, int start, int end) {
  final (int oldStart, int newStart) = _starts(ops, start);
  int oldCount = 0;
  int newCount = 0;
  for (int i = start; i < end; i++) {
    final DiffOpKind kind = ops[i].kind;
    if (kind != DiffOpKind.insert) oldCount++;
    if (kind != DiffOpKind.delete) newCount++;
  }
  out.writeln(
    '@@ -${_range(oldStart, oldCount)} +${_range(newStart, newCount)} @@',
  );
  for (int i = start; i < end; i++) {
    final DiffOp op = ops[i];
    out.writeln('${_prefix(op.kind)}${op.text}');
  }
}

String _range(int start, int count) => count == 1 ? '$start' : '$start,$count';

String _prefix(DiffOpKind kind) => switch (kind) {
      DiffOpKind.equal => ' ',
      DiffOpKind.delete => '-',
      DiffOpKind.insert => '+',
    };

/// 计算 [start] 位置对应的旧 / 新文件行号（1 起）。
(int, int) _starts(List<DiffOp> ops, int start) {
  int oldLine = 1;
  int newLine = 1;
  for (int i = 0; i < start; i++) {
    final DiffOpKind kind = ops[i].kind;
    if (kind != DiffOpKind.insert) oldLine++;
    if (kind != DiffOpKind.delete) newLine++;
  }
  return (oldLine, newLine);
}
