/// 权限匹配用的路径规范化与工作区边界判定。
///
/// 匹配器只做字符串通配，因此路径必须在进入引擎前统一：展开 `~`、把 `\` 归一
/// 为 `/`、折叠 `.` / `..` 与重复分隔符。符号链接不在此层解析（避免在纯规则
/// 层引入 IO；需要真实路径时由 fs 接缝负责）。
library;

import 'dart:io';

/// 规范化 [path]：供规则匹配与「工作区外」判定共用。
String normalizePermissionPath(String path, {Map<String, String>? env}) {
  String value = path.trim().replaceAll('\\', '/');
  value = _expandHome(value, env);
  final RegExp drive = RegExp(r'^([A-Za-z]:)');
  final String? drivePrefix = drive.firstMatch(value)?.group(1);
  if (drivePrefix != null) value = value.substring(drivePrefix.length);
  final bool absolute = value.startsWith('/');
  final List<String> parts = <String>[];
  for (final String part in value.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isNotEmpty && parts.last != '..') {
        parts.removeLast();
      } else if (!absolute) {
        parts.add(part);
      }
      continue;
    }
    parts.add(part);
  }
  final String joined = parts.join('/');
  final String base = drivePrefix ?? '';
  if (absolute) return '$base/$joined';
  return joined.isEmpty ? base : '$base$joined';
}

/// [path] 是否在 [workdir] 之内（相对路径视为在工作区内）。
bool permissionPathUnder(String path, String workdir) {
  final String candidate = normalizePermissionPath(path);
  if (!_absolute(candidate)) return true;
  final String root = normalizePermissionPath(workdir);
  if (root.isEmpty) return true;
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

String _expandHome(String value, Map<String, String>? env) {
  if (value != '~' && !value.startsWith('~/')) return value;
  final Map<String, String> source = env ?? Platform.environment;
  final String home =
      source['HOME'] ?? source['USERPROFILE'] ?? '';
  if (home.isEmpty) return value;
  return '${home.replaceAll('\\', '/')}/${value.substring(1)}';
}

bool _absolute(String path) =>
    path.startsWith('/') || RegExp(r'^[A-Za-z]:/').hasMatch(path);

String _fold(String path) =>
    Platform.isMacOS || Platform.isWindows ? path.toLowerCase() : path;
