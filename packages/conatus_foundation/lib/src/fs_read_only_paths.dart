/// 只读路径判定的通用助手：规范拼写、段级「相同或子孙」比较、祖先解析。
///
/// 产品策略（哪些目录只读、错误码与文案）留在消费方；这里只放与业务无关的
/// 路径运算，供 [ReadOnlyPathGuard] 与各宿主共用。
library;

import 'dart:io';

/// 段级「相同或子孙」判定：`foo-backup` 不算 `foo`。
///
/// macOS / Windows 默认文件系统大小写不敏感，统一按小写比较——
/// `.CONFIG/x` 在 APFS 上就是 `.config/x`，不能放过。代价是
/// 大小写敏感卷上会略微多拒，可接受。
bool underReadOnlyRoot(String path, String root) {
  if (path.isEmpty || root.isEmpty) return false;
  final String candidate = _comparable(path);
  final String base = _comparable(root);
  if (candidate == base) return true;
  final String prefix = base.endsWith(Platform.pathSeparator)
      ? base
      : '$base${Platform.pathSeparator}';
  return candidate.startsWith(prefix);
}

/// 取 [path] 的真实路径：存在则直接解析；否则解析**最近的已存在祖先**
/// 再拼回余下段（与 `fs_local_paths.dart` 的 `_identityViaAncestor` 同法）。
///
/// 受保护根常常尚未创建（用户还没装对应目录），此时整个解析会抛
/// `FileSystemException`；必须退回祖先解析，否则规范拼写为空、闸门 fail-open。
/// 没有任何已存在祖先时返回 null（调用方退回字面拼写）。
String? realPathViaAncestor(String path) {
  final List<String> trailing = <String>[];
  String current = normalizeReadOnlyPath(path);
  while (true) {
    try {
      final String real = Directory(current).resolveSymbolicLinksSync();
      return trailing.isEmpty ? real : _join(real, trailing.reversed);
    } on FileSystemException {
      final int cut = current.lastIndexOf(Platform.pathSeparator);
      if (cut <= 0) return null;
      trailing.add(current.substring(cut + 1));
      current = current.substring(0, cut);
    }
  }
}

/// 去掉冗余的 `.` / `..` 与末尾分隔符（不解析符号链接）。
///
/// Windows 盘符单独保留：`C:\foo` 不能变成 `\C:\foo`（多了前缀分隔符后
/// 既不像绝对路径，也不再与 `Directory(path).absolute.path` 的拼写一致）。
String normalizeReadOnlyPath(String path) {
  final RegExp separators = RegExp(r'[/\\]');
  final String value = path.trim().replaceAll('\\', '/');
  final RegExpMatch? drive = RegExp(r'^([A-Za-z]:)').firstMatch(value);
  final String drivePrefix = drive?.group(1) ?? '';
  final String rest =
      drivePrefix.isEmpty ? value : value.substring(drivePrefix.length);
  final bool absolute = rest.startsWith('/');
  final List<String> parts = <String>[];
  for (final String part in rest.split(separators)) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..' && parts.isNotEmpty && parts.last != '..') {
      parts.removeLast();
    } else {
      parts.add(part);
    }
  }
  final String joined = parts.join(Platform.pathSeparator);
  if (drivePrefix.isNotEmpty) {
    final String separator = Platform.pathSeparator;
    return absolute ? '$drivePrefix$separator$joined' : '$drivePrefix$joined';
  }
  return absolute ? '${Platform.pathSeparator}$joined' : joined;
}

String _comparable(String path) =>
    Platform.isMacOS || Platform.isWindows ? path.toLowerCase() : path;

String _join(String base, Iterable<String> segments) => normalizeReadOnlyPath(
      '$base${Platform.pathSeparator}${segments.join(Platform.pathSeparator)}',
    );
