part of 'fs_local.dart';

final RegExp _separators = RegExp(r'[/\\]');
final RegExp _windowsDrive = RegExp(r'^[A-Za-z]:[/\\]');

Future<FsTarget> _resolveLocal(String base, String path, String? cwd) async {
  if (path.trim().isEmpty) {
    throw const FsError(
        FsErrorCode.notFound, 'file_path must be a non-empty string');
  }
  final String displayPath = _normalize(_absolute(path, cwd ?? base));
  return FsTarget(
    targetKey: await _identity(displayPath),
    displayPath: displayPath,
  );
}

Future<FsInfo?> _statTarget(FsTarget target) async {
  final FileStat info = await FileStat.stat(target.targetKey);
  if (info.type == FileSystemEntityType.notFound) return null;
  return FsInfo(
    version: _version(info),
    type: _typeOf(info.type),
    size: info.type == FileSystemEntityType.file ? info.size : null,
  );
}

Future<FsPathInfo?> _lstatPath(String base, String path, String? cwd) async {
  final String resolved = _normalize(_absolute(path, cwd ?? base));
  final FileSystemEntityType type =
      FileSystemEntity.typeSync(resolved, followLinks: false);
  if (type == FileSystemEntityType.notFound) return null;
  final FileStat info = await FileStat.stat(resolved);
  return FsPathInfo(
    version: _version(info),
    type: type == FileSystemEntityType.link
        ? FsFileType.symlink
        : _typeOf(info.type),
    size: info.type == FileSystemEntityType.file ? info.size : null,
  );
}

bool _pathContains(String parent, String child) {
  final String base = _normalize(parent);
  final String candidate = _normalize(child);
  if (candidate == base) return true;
  final String prefix = base.endsWith(Platform.pathSeparator)
      ? base
      : '$base${Platform.pathSeparator}';
  return candidate.startsWith(prefix);
}

Future<String> _identity(String displayPath) async {
  try {
    return await File(displayPath).resolveSymbolicLinks();
  } on FileSystemException {
    // 目标不存在：对父目录取真实路径再拼回 basename，键在目录创建后仍稳定。
    final String parent = _dirname(displayPath);
    final String base = _basename(displayPath);
    try {
      final String realParent = await Directory(parent).resolveSymbolicLinks();
      return _normalize('$realParent${Platform.pathSeparator}$base');
    } on FileSystemException {
      return displayPath;
    }
  }
}

String _absolute(String path, String cwd) =>
    _isAbsolute(path) ? path : _join(cwd, path);

bool _isAbsolute(String path) =>
    path.startsWith('/') || _windowsDrive.hasMatch(path);

String _join(String base, String child) =>
    _normalize('$base${Platform.pathSeparator}$child');

String _normalize(String path) {
  final bool absolute = _isAbsolute(path);
  final List<String> parts = <String>[];
  for (final String part in path.split(_separators)) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..' && parts.isNotEmpty && parts.last != '..') {
      parts.removeLast();
    } else {
      parts.add(part);
    }
  }
  final String joined = parts.join(Platform.pathSeparator);
  return absolute ? '${Platform.pathSeparator}$joined' : joined;
}

String _dirname(String path) {
  final int index = path.lastIndexOf(Platform.pathSeparator);
  if (index < 0) return '.';
  if (index == 0) return Platform.pathSeparator;
  return path.substring(0, index);
}

String _basename(String path) {
  final int index = path.lastIndexOf(Platform.pathSeparator);
  return index < 0 ? path : path.substring(index + 1);
}

String _version(FileStat info) =>
    '${info.changed.microsecondsSinceEpoch}:${info.modified.microsecondsSinceEpoch}:${info.size}';

FsFileType _typeOf(FileSystemEntityType type) => switch (type) {
      FileSystemEntityType.file => FsFileType.file,
      FileSystemEntityType.directory => FsFileType.directory,
      FileSystemEntityType.link => FsFileType.symlink,
      _ => FsFileType.other,
    };
