/// 权限匹配用的路径规范化与工作区边界判定。
///
/// 匹配器只做字符串通配，因此路径必须在进入引擎前统一：展开 `~`、把 `\` 归一
/// 为 `/`、折叠 `.` / `..` 与重复分隔符。相对路径在判定工作区边界时按 workdir
/// 解析（`../../etc/passwd` 因此不能伪装成「工作区内」）。符号链接不在此层
/// 解析（纯规则层不做 IO；需要真实路径时由 fs 接缝负责）。
library;

import 'dart:io';

/// 规范化 [path]：供规则匹配与「工作区外」判定共用。
String normalizePermissionPath(String path, {Map<String, String>? env}) {
  String value = path.trim().replaceAll('\\', '/');
  value = _expandHome(value, env);
  final RegExpMatch? drive = RegExp(r'^([A-Za-z]:)').firstMatch(value);
  final String drivePrefix = drive?.group(1) ?? '';
  if (drivePrefix.isNotEmpty) value = value.substring(drivePrefix.length);
  final bool absolute = value.startsWith('/');
  final List<String> parts = _collapse(value, absolute);
  final String joined = parts.join('/');
  if (absolute) return '$drivePrefix/$joined';
  return joined.isEmpty ? drivePrefix : '$drivePrefix$joined';
}

/// 把相对路径按 [workdir] 解析成绝对路径；绝对路径原样规范化。
String resolvePermissionPath(String path, String workdir) {
  final String normalized = normalizePermissionPath(path);
  if (_absolute(normalized)) return normalized;
  final String root = normalizePermissionPath(workdir);
  if (root.isEmpty) return normalized;
  return normalizePermissionPath('$root/$normalized');
}

/// [path] 是否在 [workdir] 之内；相对路径先按 workdir 解析。
bool permissionPathUnder(String path, String workdir) {
  final String root = normalizePermissionPath(workdir);
  if (root.isEmpty) return true;
  final String candidate = resolvePermissionPath(path, root);
  final String left = _fold(candidate);
  final String right = _fold(root);
  if (left == right) return true;
  final String prefix = right.endsWith('/') ? right : '$right/';
  return left.startsWith(prefix);
}

/// 路径所在目录的边界 pattern（`/a/b.txt` → `/a/*`；根目录 → `/*`）。
String permissionDirectoryBoundary(String path) {
  final String normalized = normalizePermissionPath(path);
  final int cut = normalized.lastIndexOf('/');
  if (cut < 0) return '*';
  if (cut == 0) return '/*';
  return '${normalized.substring(0, cut)}/*';
}

/// 折叠 `.` / `..` / 空段。
List<String> _collapse(String value, bool absolute) {
  final List<String> parts = <String>[];
  for (final String part in value.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..' && parts.isNotEmpty && parts.last != '..') {
      parts.removeLast();
    } else if (part == '..' && !absolute) {
      parts.add(part);
    } else if (part != '..') {
      parts.add(part);
    }
  }
  return parts;
}

String _expandHome(String value, Map<String, String>? env) {
  if (value != '~' && !value.startsWith('~/')) return value;
  final Map<String, String> source = env ?? Platform.environment;
  final String home = source['HOME'] ?? source['USERPROFILE'] ?? '';
  if (home.isEmpty) return value;
  return '${home.replaceAll('\\', '/')}/${value.substring(1)}';
}

bool _absolute(String path) =>
    path.startsWith('/') || RegExp(r'^[A-Za-z]:/').hasMatch(path);

String _fold(String path) =>
    Platform.isMacOS || Platform.isWindows ? path.toLowerCase() : path;
