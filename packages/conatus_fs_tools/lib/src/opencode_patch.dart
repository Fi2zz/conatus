/// OpenCode / Codex `***` 补丁格式的解析。
///
/// 支持：
/// - `*** Add File: path`（`+` 内容行）
/// - `*** Update File: path`（`@@` 分块，` ` / `-` / `+` 行，可选 `*** Move to:`）
/// - `*** Delete File: path`
/// - 外层 `*** Begin Patch` / `*** End Patch`
library;

/// 一条补丁操作。
sealed class OpenCodePatchOp {
  const OpenCodePatchOp(this.path);

  /// 目标路径。
  final String path;
}

/// 新增文件。
final class AddFileOp extends OpenCodePatchOp {
  const AddFileOp(super.path, this.content);

  /// 文件内容（含尾随换行，若提供了非空内容）。
  final String content;
}

/// 删除文件。
final class DeleteFileOp extends OpenCodePatchOp {
  const DeleteFileOp(super.path);
}

/// 更新文件；[moveTo] 非空时写新路径并删除旧路径。
final class UpdateFileOp extends OpenCodePatchOp {
  const UpdateFileOp(super.path, this.chunks, {this.moveTo});

  final List<UpdateChunk> chunks;
  final String? moveTo;
}

/// 一个 `@@` 块：`oldLines` 用于定位，`newLines` 用于替换。
final class UpdateChunk {
  const UpdateChunk(
      {this.anchor, required this.oldLines, required this.newLines});

  /// `@@` 后的上下文提示（可空）。
  final String? anchor;

  /// 上下文行 + 删除行。
  final List<String> oldLines;

  /// 上下文行 + 新增行。
  final List<String> newLines;
}

/// 解析补丁；格式错误抛 [FormatException]。
List<OpenCodePatchOp> parseOpenCodePatch(String text) {
  final List<String> lines = <String>[
    for (final String line in text.split('\n'))
      line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
  ];
  final List<OpenCodePatchOp> ops = <OpenCodePatchOp>[];
  int index = 0;
  while (index < lines.length) {
    final String line = lines[index];
    if (line.trim().isEmpty ||
        line.startsWith('*** Begin Patch') ||
        line.startsWith('*** End Patch')) {
      index++;
      continue;
    }
    if (line.startsWith('*** Add File:')) {
      final String path = _path(line, '*** Add File:');
      final _Section section = _collect(lines, index + 1);
      ops.add(AddFileOp(path, _addContent(section.lines)));
      index = section.next;
      continue;
    }
    if (line.startsWith('*** Delete File:')) {
      final String path = _path(line, '*** Delete File:');
      final _Section section = _collect(lines, index + 1);
      ops.add(DeleteFileOp(path));
      index = section.next;
      continue;
    }
    if (line.startsWith('*** Update File:')) {
      final String path = _path(line, '*** Update File:');
      final _Section section = _collect(lines, index + 1);
      ops.add(_update(path, section.lines));
      index = section.next;
      continue;
    }
    throw FormatException('未知的补丁头：$line');
  }
  if (ops.isEmpty) throw const FormatException('补丁为空');
  return ops;
}

class _Section {
  const _Section(this.lines, this.next);

  final List<String> lines;
  final int next;
}

/// 收集到下一个 `*** ...` 头之前；头部本身不计入。
_Section _collect(List<String> lines, int start) {
  int index = start;
  while (index < lines.length &&
      (!lines[index].startsWith('*** ') ||
          lines[index].startsWith('*** Move to:'))) {
    index++;
  }
  return _Section(lines.sublist(start, index), index);
}

String _path(String line, String prefix) {
  final String path = line.substring(prefix.length).trim();
  if (path.isEmpty) throw FormatException('$prefix 缺少路径');
  return path;
}

String _addContent(List<String> lines) {
  final List<String> content = <String>[];
  for (final String line in lines) {
    if (line.startsWith('+')) {
      content.add(line.substring(1));
    } else if (line.isNotEmpty) {
      content.add(line);
    }
  }
  return content.isEmpty ? '' : '${content.join('\n')}\n';
}

UpdateFileOp _update(String path, List<String> lines) {
  String? moveTo;
  final List<UpdateChunk> chunks = <UpdateChunk>[];
  String? anchor;
  List<String>? oldLines;
  List<String>? newLines;
  void flush() {
    if (oldLines == null && newLines == null) return;
    chunks.add(
      UpdateChunk(
        anchor: anchor,
        oldLines: List<String>.unmodifiable(oldLines ?? const <String>[]),
        newLines: List<String>.unmodifiable(newLines ?? const <String>[]),
      ),
    );
    anchor = null;
    oldLines = null;
    newLines = null;
  }

  for (final String line in lines) {
    if (line.startsWith('*** Move to:')) {
      moveTo = line.substring('*** Move to:'.length).trim();
      continue;
    }
    if (line.startsWith('@@')) {
      flush();
      anchor = line.substring(2).trim();
      oldLines = <String>[];
      newLines = <String>[];
      continue;
    }
    if (line == r'\ No newline at end of file') continue;
    if (line.isEmpty) continue;
    final List<String> olds = oldLines ??= <String>[];
    final List<String> news = newLines ??= <String>[];
    final String prefix = line.substring(0, 1);
    final String text = line.substring(1);
    if (prefix != ' ' && prefix != '+' && prefix != '-') {
      throw FormatException('无法识别的补丁行：$line');
    }
    if (prefix == ' ' || prefix == '-') olds.add(text);
    if (prefix == ' ' || prefix == '+') news.add(text);
  }
  flush();
  if (chunks.isEmpty && moveTo == null) {
    throw const FormatException('Update File 既没有 hunk 也没有 Move to');
  }
  return UpdateFileOp(path, List<UpdateChunk>.unmodifiable(chunks),
      moveTo: moveTo);
}
