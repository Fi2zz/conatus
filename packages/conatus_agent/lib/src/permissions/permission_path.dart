/// 权限匹配用的路径规范化与工作区边界判定。
///
/// 匹配器只做字符串通配，因此路径必须在进入引擎前统一：展开 `~`、把 `\` 归一
/// 为 `/`、折叠 `.` / `..` 与重复分隔符。相对路径在判定工作区边界时按 workdir
/// 解析（`../../etc/passwd` 因此不能伪装成「工作区内」）。
///
/// 规则匹配按**同一目标的所有拼写**进行：词法拼写、按 workdir 解析后的拼写、
/// 以及已存在路径的真实路径（符号链接取真实身份）。只看词法拼写会让
/// `edit "src/*"` 挡不住 `write_file("/abs/work/src/x")`，也会让工作区里
/// 指向 `/etc/hosts` 的链接绕过 `deny read "/etc/*"` 与 `external_directory`。
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

/// [path] 参与规则匹配的全部拼写（词法 / 按 workdir 解析 / 真实路径）。
///
/// 真实路径解析是 best-effort：路径（或其最近已存在祖先）解析失败时只用前两
/// 种。返回顺序稳定（词法在前），去重后供 `PermissionEngine` 逐条匹配。
List<String> permissionPathSpellings(String path, String? workdir) {
  final String lexical = normalizePermissionPath(path);
  final String resolved = workdir == null || workdir.isEmpty
      ? lexical
      : resolvePermissionPath(lexical, workdir);
  final Set<String> spellings = <String>{lexical, resolved};
  final String? real = canonicalPermissionPath(resolved);
  if (real != null) spellings.add(normalizePermissionPath(real));
  return spellings.toList(growable: false);
}

/// 规则 pattern 的拼写展开：词法 + 按 workdir 解析 + 静态前缀的真实路径。
///
/// pattern 可能含 `*` / `?`；真实路径只能解析第一个通配符之前的目录，再把
/// 通配符之后的尾巴原样接回。无法解析时只返回前两种拼写。
List<String> permissionPatternSpellings(String pattern, String? workdir) {
  final String lexical = normalizePermissionPath(pattern);
  final String resolved = workdir == null || workdir.isEmpty
      ? lexical
      : resolvePermissionPath(lexical, workdir);
  final Set<String> spellings = <String>{lexical, resolved};
  final String? real = canonicalPermissionPattern(resolved);
  if (real != null) spellings.add(real);
  return spellings.toList(growable: false);
}

/// [path] 的真实路径拼写；不存在时沿最近的已存在祖先解析再拼回余下段。
///
/// 纯规则层此前不做 IO；这里只读元数据（`resolveSymbolicLinks` / 类型查询），
/// 不创建 / 不修改任何文件。没有任何可解析的祖先时返回 `null`。
String? canonicalPermissionPath(String path) {
  final String normalized = normalizePermissionPath(path);
  final List<String> trailing = <String>[];
  String current = normalized;
  while (true) {
    try {
      final String real =
          File(current).resolveSymbolicLinksSync().replaceAll('\\', '/');
      return trailing.isEmpty ? real : _append(real, trailing.reversed);
    } on FileSystemException {
      final int cut = current.lastIndexOf('/');
      if (cut <= 0) return null;
      trailing.add(current.substring(cut + 1));
      current = current.substring(0, cut);
    }
  }
}

/// 带通配符 pattern 的真实路径：只解析静态前缀目录。
String? canonicalPermissionPattern(String pattern) {
  final int wildcard = _firstWildcard(pattern);
  if (wildcard < 0) return canonicalPermissionPath(pattern);
  final int slash = pattern.lastIndexOf('/', wildcard);
  if (slash < 0) return null;
  final String prefix = slash == 0 ? '/' : pattern.substring(0, slash);
  final String? real = canonicalPermissionPath(prefix);
  return real == null ? null : '$real${pattern.substring(slash)}';
}

int _firstWildcard(String value) {
  final int star = value.indexOf('*');
  final int question = value.indexOf('?');
  if (star < 0) return question;
  if (question < 0) return star;
  return star < question ? star : question;
}

String _append(String base, Iterable<String> segments) =>
    normalizePermissionPath('$base/${segments.join('/')}');

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
