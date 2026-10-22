/// 从 `apply_patch` 的补丁文本提取受影响路径。
///
/// 支持两种头：
/// - `*** Add File:` / `*** Update File:` / `*** Delete File:` / `*** Move to:`
/// - 统一 diff 的 `--- a/` / `+++ b/`（`/dev/null` 侧退回另一侧）
///
/// 提取结果规范化并去重；解析不出任何路径时返回空列表（调用方落回 `*`）。
library;

import 'permission_path.dart';

/// 补丁里出现的文件头前缀。
const List<String> _patchHeaders = <String>[
  '*** Add File:',
  '*** Update File:',
  '*** Delete File:',
  '*** Move to:',
];

/// 提取 [patch] 中所有受影响路径（已规范化、去重、保持出现顺序）。
List<String> permissionPatchPaths(String patch) {
  final List<String> paths = <String>[];
  String? oldPath;
  for (final String raw in patch.split('\n')) {
    final String line = raw.trimRight();
    final String? headerPath = _headerPath(line);
    if (headerPath != null) {
      _add(paths, headerPath);
      continue;
    }
    if (line.startsWith('+++ ')) {
      oldPath = _addUnifiedSide(paths, line.substring(4).trim(), oldPath);
      continue;
    }
    if (line.startsWith('--- ')) {
      if (oldPath != null) _add(paths, oldPath);
      oldPath = _stripPrefix(line.substring(4).trim());
    }
  }
  if (oldPath != null) _add(paths, oldPath);
  return paths;
}

/// `*** ...:` 头；不是已知头返回 `null`。
String? _headerPath(String line) {
  for (final String header in _patchHeaders) {
    if (line.startsWith(header)) {
      final String value = line.substring(header.length).trim();
      return value.isEmpty ? null : value;
    }
  }
  return null;
}

/// 处理统一 diff 的 `+++` 侧；返回新的「旧侧待定路径」。
String? _addUnifiedSide(
  List<String> paths,
  String value,
  String? oldPath,
) {
  if (value == '/dev/null') return oldPath;
  _add(paths, _stripPrefix(value));
  return null;
}

/// 去掉 git 的 `a/` / `b/` 前缀。
String _stripPrefix(String value) {
  if (value.startsWith('a/') || value.startsWith('b/')) {
    return value.substring(2);
  }
  return value;
}

void _add(List<String> paths, String raw) {
  final String path = normalizePermissionPath(raw);
  if (path.isEmpty || path == '/dev/null') return;
  if (!paths.contains(path)) paths.add(path);
}
