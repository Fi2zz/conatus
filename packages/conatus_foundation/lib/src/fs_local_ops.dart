part of 'fs_local.dart';

Future<String> _readTargetText(FsTarget target) async {
  final FileStat info = await FileStat.stat(target.targetKey);
  if (info.type == FileSystemEntityType.notFound) {
    throw FsError(
        FsErrorCode.notFound, 'cannot read "${target.displayPath}": not found');
  }
  if (info.type != FileSystemEntityType.file) {
    throw FsError(FsErrorCode.notRegularFile,
        'cannot read "${target.displayPath}": not a regular file');
  }
  final List<int> bytes = await File(target.targetKey).readAsBytes();
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw FsError(FsErrorCode.notText,
        'cannot read "${target.displayPath}": invalid UTF-8 text');
  }
}

Future<List<FsDirEntry>> _listTargetDir(FsTarget target) async {
  final FileStat info = await FileStat.stat(target.targetKey);
  if (info.type == FileSystemEntityType.notFound) {
    throw FsError(
        FsErrorCode.notFound, 'cannot list "${target.displayPath}": not found');
  }
  if (info.type != FileSystemEntityType.directory) {
    throw FsError(FsErrorCode.notDirectory,
        'cannot list "${target.displayPath}": not a directory');
  }
  final List<FsDirEntry> entries = <FsDirEntry>[];
  await for (final FileSystemEntity entity
      in Directory(target.targetKey).list(followLinks: false)) {
    final String name = _basename(entity.path);
    final FileStat childInfo = await FileStat.stat(entity.path);
    entries.add(FsDirEntry(
      name: name,
      type: _typeOf(childInfo.type),
      target: FsTarget(
        targetKey: entity.path,
        displayPath: '${target.displayPath}${Platform.pathSeparator}$name',
      ),
      size: childInfo.type == FileSystemEntityType.file ? childInfo.size : null,
    ));
  }
  entries.sort((FsDirEntry a, FsDirEntry b) => a.name.compareTo(b.name));
  return entries;
}

Future<FsWriteOutcome> _writeTargetText(
  FsTarget target,
  String content,
  FsWriteIntent? expected,
) async {
  final FileStat info = await FileStat.stat(target.targetKey);
  final bool exists = info.type != FileSystemEntityType.notFound;
  if (exists && info.type != FileSystemEntityType.file) {
    throw FsError(FsErrorCode.notRegularFile,
        'cannot write "${target.displayPath}": not a regular file');
  }
  _checkWriteGuard(target, expected, exists ? _version(info) : null);
  final String? before = exists ? await _readOrNull(target) : null;
  await _writeAtomic(target.targetKey, content);
  final FileStat after = await FileStat.stat(target.targetKey);
  return FsWriteOutcome(
    operation: exists ? FsWriteOperation.update : FsWriteOperation.create,
    version: _version(after),
    before: before,
    after: content,
  );
}

void _checkWriteGuard(
    FsTarget target, FsWriteIntent? expected, String? version) {
  if (expected is FsReplaceIfVersion) {
    if (version == null || version != expected.version) {
      throw FsError(FsErrorCode.staleVersion,
          'cannot write "${target.displayPath}": file changed since it was read');
    }
  } else if (expected is FsCreateIfAbsent && version != null) {
    throw FsError(FsErrorCode.notObserved,
        'cannot overwrite existing "${target.displayPath}" without reading it first');
  }
}

Future<FsEditOutcome> _editTargetText(
  FsTarget target,
  FsEditRequest edit,
  String? expectedVersion,
) async {
  final FileStat info = await FileStat.stat(target.targetKey);
  if (info.type == FileSystemEntityType.notFound) {
    throw FsError(FsErrorCode.staleVersion,
        'cannot edit "${target.displayPath}": file changed since it was read');
  }
  if (info.type != FileSystemEntityType.file) {
    throw FsError(FsErrorCode.notRegularFile,
        'cannot edit "${target.displayPath}": not a regular file');
  }
  if (expectedVersion != null && _version(info) != expectedVersion) {
    throw FsError(FsErrorCode.staleVersion,
        'cannot edit "${target.displayPath}": file changed since it was read');
  }
  final String original = await _readTargetText(target);
  final int count =
      edit.oldString.isEmpty ? 0 : original.split(edit.oldString).length - 1;
  if (count == 0) {
    throw FsError(FsErrorCode.editNotFound,
        'old_string was not found in "${target.displayPath}"');
  }
  if (!edit.replaceAll && count > 1) {
    throw FsError(FsErrorCode.ambiguousEdit,
        'old_string matched $count times in "${target.displayPath}"');
  }
  final String edited = original.split(edit.oldString).join(edit.newString);
  await _writeAtomic(target.targetKey, edited);
  final FileStat after = await FileStat.stat(target.targetKey);
  return FsEditOutcome(
    version: _version(after),
    before: original,
    after: edited,
  );
}

Future<String?> _readOrNull(FsTarget target) async {
  try {
    return await File(target.targetKey).readAsString();
  } on FormatException {
    return null;
  } on FileSystemException {
    return null;
  }
}

Future<void> _writeAtomic(String path, String content) async {
  final File file = File(path);
  await file.parent.create(recursive: true);
  final File temp = File('$path.tmp-${DateTime.now().microsecondsSinceEpoch}');
  await temp.writeAsString(content, flush: true);
  try {
    await temp.rename(path);
  } on FileSystemException {
    await file.writeAsString(content, flush: true);
    if (await temp.exists()) await temp.delete();
  }
}

Future<void> _removeTarget(FsTarget target) async {
  final FileSystemEntityType type =
      FileSystemEntity.typeSync(target.targetKey, followLinks: false);
  if (type == FileSystemEntityType.notFound) return;
  if (type == FileSystemEntityType.directory) {
    await Directory(target.targetKey).delete(recursive: true);
    return;
  }
  await File(target.targetKey).delete();
}
