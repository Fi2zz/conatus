/// `***` 补丁的应用：按上下文定位、替换、新增、删除与移动。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import 'opencode_patch.dart';

/// 应用阶段的失败（带稳定错误码）。
class OpenCodePatchException implements Exception {
  const OpenCodePatchException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

/// 按顺序应用操作；失败时已应用的文件不回滚（与 unified diff 同语义）。
Future<void> applyOpenCodeOps(
  FileSystem fs,
  List<OpenCodePatchOp> ops,
) async {
  for (final OpenCodePatchOp op in ops) {
    switch (op) {
      case AddFileOp():
        await _add(fs, op);
      case DeleteFileOp():
        await _delete(fs, op);
      case UpdateFileOp():
        await _update(fs, op);
    }
  }
}

Future<void> _add(FileSystem fs, AddFileOp op) async {
  final FsTarget target = await fs.resolve(op.path);
  if (await fs.stat(target) != null) {
    throw OpenCodePatchException('PATCH_EXISTS', '文件已存在：${op.path}');
  }
  await fs.writeText(target, op.content);
}

Future<void> _delete(FileSystem fs, DeleteFileOp op) async {
  final FsTarget target = await fs.resolve(op.path);
  if (await fs.stat(target) == null) {
    throw OpenCodePatchException('PATCH_NOT_FOUND', '文件不存在：${op.path}');
  }
  await fs.remove(target);
}

Future<void> _update(FileSystem fs, UpdateFileOp op) async {
  final FsTarget target = await fs.resolve(op.path);
  if (await fs.stat(target) == null) {
    throw OpenCodePatchException('PATCH_NOT_FOUND', '文件不存在：${op.path}');
  }
  final String oldText = await fs.readText(target);
  final String newText = applyOpenCodeUpdate(oldText, op);
  final String? moveTo = op.moveTo;
  if (moveTo == null) {
    await fs.writeText(target, newText);
    return;
  }
  final FsTarget moved = await fs.resolve(moveTo);
  if (await fs.stat(moved) != null) {
    throw OpenCodePatchException('PATCH_EXISTS', '移动目标已存在：$moveTo');
  }
  await fs.writeText(moved, newText);
  await fs.remove(target);
}

/// 把 [op] 的 hunk 应用到 [oldText]，返回新文本（保留换行风格）。
String applyOpenCodeUpdate(String oldText, UpdateFileOp op) {
  final bool crlf = oldText.contains('\r\n');
  final String normalized = crlf ? oldText.replaceAll('\r\n', '\n') : oldText;
  final bool trailing = normalized.endsWith('\n');
  final List<String> lines = <String>[
    if (normalized.isNotEmpty) ...normalized.split('\n'),
  ];
  if (trailing && lines.isNotEmpty) lines.removeLast();
  int search = 0;
  for (final UpdateChunk chunk in op.chunks) {
    final int index = _locate(lines, chunk, search, op.path);
    lines.replaceRange(
      index,
      index + chunk.oldLines.length,
      chunk.newLines,
    );
    search = index + chunk.newLines.length;
  }
  final String joined = lines.join('\n');
  final String text = trailing ? '$joined\n' : joined;
  return crlf ? text.replaceAll('\n', '\r\n') : text;
}

int _locate(
  List<String> lines,
  UpdateChunk chunk,
  int start,
  String path,
) {
  final List<String> oldLines = chunk.oldLines;
  if (oldLines.isEmpty) {
    final int? anchor = _anchor(lines, chunk.anchor, start);
    if (anchor != null) return anchor + 1;
    return start.clamp(0, lines.length);
  }
  int index = _search(lines, oldLines, start, _identity);
  index = index >= 0 ? index : _search(lines, oldLines, 0, _identity);
  index = index >= 0 ? index : _search(lines, oldLines, start, _trimRight);
  index = index >= 0 ? index : _search(lines, oldLines, 0, _trimRight);
  if (index < 0) {
    final int? anchor = _anchor(lines, chunk.anchor, start);
    if (anchor != null) {
      index = _search(lines, oldLines, anchor, _identity);
    }
  }
  if (index < 0) {
    throw OpenCodePatchException('PATCH_CONTEXT', '上下文不匹配：$path');
  }
  return index;
}

int _search(
  List<String> lines,
  List<String> oldLines,
  int start,
  String Function(String) normalize,
) {
  for (int index = start.clamp(0, lines.length);
      index + oldLines.length <= lines.length;
      index++) {
    bool matched = true;
    for (int offset = 0; offset < oldLines.length; offset++) {
      if (normalize(lines[index + offset]) != normalize(oldLines[offset])) {
        matched = false;
        break;
      }
    }
    if (matched) return index;
  }
  return -1;
}

int? _anchor(List<String> lines, String? anchor, int start) {
  if (anchor == null || anchor.isEmpty) return null;
  final String needle = anchor.trim();
  for (int index = start.clamp(0, lines.length);
      index < lines.length;
      index++) {
    if (lines[index].trim().contains(needle)) return index;
  }
  return null;
}

String _identity(String value) => value;

String _trimRight(String value) => value.trimRight();
