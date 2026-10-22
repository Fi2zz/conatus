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

import 'dart:convert';

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

/// 清洗 `---` / `+++` 的路径：去时间戳、去 `a/` / `b/`、还原 git 的引号与
/// 八进制转义。
///
/// 与 `diff_paths.dart` 的 `cleanDiffPath` 同语义（conatus_agent 不依赖
/// conatus_code，故此处独立实现）。不做这一步时，带空格 / 非 ASCII 的文件
/// 名会以 `"a/x y"` / `\346\226\207` 的形态进规则匹配，针对真实路径的 deny
/// 规则会漏。
String _unifiedPath(String raw) {
  int value = 0;
  String text = raw.trim();
  final int tab = text.indexOf('\t');
  if (tab >= 0) text = text.substring(0, tab);
  text = text.trim();
  text = _unquote(text);
  if (text.startsWith('a/') || text.startsWith('b/')) {
    value = 2;
  }
  return text.substring(value);
}

/// 还原 git 的引号形式（`"a/x y"`、`\\`、`\"`、`\t`、`\n`）与八进制字节转义。
String _unquote(String value) {
  if (value.length < 2 || !value.startsWith('"') || !value.endsWith('"')) {
    return value;
  }
  final String body = value.substring(1, value.length - 1);
  final StringBuffer out = StringBuffer();
  int index = 0;
  while (index < body.length) {
    if (body[index] == '\\' && _octalAt(body, index + 1)) {
      final List<int> bytes = <int>[];
      while (index + 3 < body.length && _octalAt(body, index + 1)) {
        bytes.add(int.parse(body.substring(index + 1, index + 4), radix: 8));
        index += 4;
      }
      out.write(utf8.decode(bytes, allowMalformed: true));
      continue;
    }
    if (body[index] == '\\' && index + 1 < body.length) {
      index++;
      out.write(_unescape(body[index]));
    } else {
      out.write(body[index]);
    }
    index++;
  }
  return out.toString();
}

/// 下标处是否是三个八进制数字（git 的字节转义）。
bool _octalAt(String value, int index) {
  if (index + 3 > value.length) return false;
  for (int i = index; i < index + 3; i++) {
    if (value.codeUnitAt(i) < 0x30 || value.codeUnitAt(i) > 0x37) return false;
  }
  return true;
}

String _unescape(String char) => switch (char) {
      'n' => '\n',
      't' => '\t',
      'r' => '\r',
      _ => char,
    };

void _add(List<String> paths, String raw) {
  final String path = normalizePermissionPath(raw);
  if (path.isEmpty || path == '/dev/null') return;
  if (!paths.contains(path)) paths.add(path);
}
