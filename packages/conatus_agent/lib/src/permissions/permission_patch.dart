/// 从 `apply_patch` 的补丁文本提取受影响路径。
///
/// 支持两种头：
/// - `*** Add File:` / `*** Update File:` / `*** Delete File:` / `*** Move to:`
/// - 统一 diff 的 `--- a/` / `+++ b/`
///
/// 统一 diff 的**两侧路径都保留**：工具实际写入的是 `---` 侧（见 `diff_parse.dart`
/// 与 `apply_patch.dart`），只取 `+++` 会让针对旧路径的 deny 规则被绕过。
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
    if (line.startsWith('--- ')) {
      if (oldPath != null) _add(paths, oldPath);
      oldPath = _unifiedPath(line.substring(4));
      continue;
    }
    if (line.startsWith('+++ ')) {
      _addUnifiedPair(paths, line.substring(4), oldPath);
      oldPath = null;
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

/// 统一 diff：新侧与旧侧都计入（`/dev/null` 侧跳过）。
void _addUnifiedPair(List<String> paths, String rawNew, String? oldPath) {
  final String newPath = _unifiedPath(rawNew);
  if (newPath != '/dev/null') _add(paths, newPath);
  if (oldPath != null) _add(paths, oldPath);
}

/// 去掉 git 的 `a/` / `b/` 前缀。
String _unifiedPath(String raw) {
  final String value = raw.trim();
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
