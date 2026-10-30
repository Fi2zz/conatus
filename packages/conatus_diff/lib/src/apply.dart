/// diff 应用的纯函数面：从工具类与审批预览里提出来，供「算出执行后内容」
/// 的事前审阅门复用（与真实工具同一语义，避免两套实现漂移）。
library;

import 'diff_types.dart';
import 'unified_diff.dart';

/// 上下文行与现有内容不匹配（patch 不适用）。
class PatchContextException implements Exception {
  /// 以人类可读的 [message] 构造。
  const PatchContextException(this.message);

  /// 失配说明。
  final String message;

  @override
  String toString() => message;
}

/// 把 [file] 的所有 hunk 应用到 [oldText]（倒序避免行号漂移），返回新
/// 文本；上下文行不匹配抛 [PatchContextException]。尾随换行保持原样。
String applyDiffFile(String oldText, DiffFile file) {
  final List<String> lines = List<String>.of(splitLines(oldText));
  final bool trailingNewline = oldText.endsWith('\n');
  for (final DiffHunk hunk in file.hunks.reversed) {
    _applyHunk(lines, hunk, file.path);
  }
  return '${lines.join('\n')}${trailingNewline ? '\n' : ''}';
}

/// 应用一个 hunk：校验上下文行与现有内容逐行相等，替换为新侧内容。
// REASON: diff 应用是既定算法实现，前缀分支即 hunk 行语义本身。
void _applyHunk(List<String> lines, DiffHunk hunk, String path) {
  final int start = hunk.oldStart < 1 ? 0 : hunk.oldStart - 1;
  if (start > lines.length) {
    throw PatchContextException('起始行越界：$path 第 ${hunk.oldStart} 行');
  }
  int pos = start;
  final List<String> replacement = <String>[];
  for (final String raw in hunk.lines) {
    final String prefix = raw.substring(0, 1);
    final String text = raw.substring(1);
    if (prefix == '+') {
      replacement.add(text);
    } else if (prefix == '-' || prefix == ' ') {
      if (pos >= lines.length || lines[pos] != text) {
        throw PatchContextException('上下文不匹配：$path 第 ${pos + 1} 行');
      }
      pos++;
      if (prefix == ' ') replacement.add(text);
    }
  }
  lines.replaceRange(start, pos, replacement);
}

/// 与 EditFileTool 相同的字面替换语义；old_string 不存在、多处匹配而未
/// replace_all、或新旧相同（无意义编辑）时返回 `null`——这些情形真实工具
/// 会报错，调用方应 fail-open 放行。
String? applyEditText(
  String text,
  String oldString,
  String newString,
  bool replaceAll,
) {
  if (oldString == newString) return null;
  final int matches = oldString.allMatches(text).length;
  if (matches == 0) return null;
  if (matches > 1 && !replaceAll) return null;
  return replaceAll
      ? text.replaceAll(oldString, newString)
      : text.replaceFirst(oldString, newString);
}
