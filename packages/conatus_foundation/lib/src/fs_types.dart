/// filesystem 能力缝的词汇：目标/版本标识、元数据、写入意图与结局、
/// 字面替换请求，以及稳定的错误码。
library;

/// 稳定的、可路由的文件系统错误码。
enum FsErrorCode {
  notFound('FS_NOT_FOUND'),
  notDirectory('FS_NOT_DIRECTORY'),
  notText('FS_NOT_TEXT'),
  notRegularFile('FS_NOT_REGULAR_FILE'),
  tooLarge('FS_TOO_LARGE'),
  permissionDenied('FS_PERMISSION_DENIED'),
  sandboxDenied('FS_SANDBOX_DENIED'),
  ioError('FS_IO_ERROR'),
  staleVersion('FS_STALE_VERSION'),
  notObserved('FS_NOT_OBSERVED'),
  ambiguousEdit('FS_AMBIGUOUS_EDIT'),
  editNotFound('FS_EDIT_NOT_FOUND'),
  aborted('FS_ABORTED');

  const FsErrorCode(this.code);

  /// 线上错误码字符串。
  final String code;
}

/// 带稳定错误码的文件系统异常。
class FsError implements Exception {
  const FsError(this.code, this.message);

  /// 机器可路由的错误码。
  final FsErrorCode code;

  /// 人可读的消息。
  final String message;

  @override
  String toString() => 'FsError(${code.code}): $message';
}

/// 路径条目类型（[symlink] 只可能来自不跟随链接的 [FileSystem.lstat]）。
enum FsFileType { file, directory, symlink, other }

/// 由后端解析出的稳定目标身份；[FileSystem.resolve] 产出它，其余操作接收它。
class FsTarget {
  const FsTarget({required this.targetKey, required this.displayPath});

  /// 不透明键：用于陈旧守卫与目标查找，消费方不得解析。
  final String targetKey;

  /// 面向模型/界面的路径（可能是绝对路径、相对路径或远端 URI）。
  final String displayPath;

  @override
  String toString() => 'FsTarget($displayPath)';
}

/// [FileSystem.stat] 返回的元数据；目标不存在时为 null。
class FsInfo {
  const FsInfo({required this.version, required this.type, this.size});

  /// 不透明的新鲜度令牌。
  final String version;

  /// 目标类型。
  final FsFileType type;

  /// 普通文件的字节大小。
  final int? size;
}

/// 不跟随链接的路径元数据（[FileSystem.lstat]）。
class FsPathInfo {
  const FsPathInfo({required this.version, required this.type, this.size});

  /// 不透明的新鲜度令牌。
  final String version;

  /// 路径条目类型（可能是 [FsFileType.symlink]）。
  final FsFileType type;

  /// 字节大小。
  final int? size;
}

/// [FileSystem.listDir] 返回的一个直接子项：只含元数据与已解析目标。
class FsDirEntry {
  const FsDirEntry({
    required this.name,
    required this.type,
    required this.target,
    this.size,
  });

  /// 子项在目录内的 basename。
  final String name;

  /// 子项类型。
  final FsFileType type;

  /// 已解析的子项目标。
  final FsTarget target;

  /// 普通文件的字节大小。
  final int? size;
}

/// 带守卫的写入意图。
///
/// 从 `writeText` 省略意图表示无条件创建/覆盖；[FsCreateIfAbsent] 拒绝已存在
/// 的目标（`FS_NOT_OBSERVED`），[FsReplaceIfVersion] 拒绝缺失或版本不符
/// （`FS_STALE_VERSION`）。
sealed class FsWriteIntent {
  const FsWriteIntent();
}

/// 仅在目标不存在时创建；已存在则 `FS_NOT_OBSERVED`。
class FsCreateIfAbsent extends FsWriteIntent {
  const FsCreateIfAbsent();
}

/// 仅在目标仍处于 [version] 时替换。
class FsReplaceIfVersion extends FsWriteIntent {
  const FsReplaceIfVersion(this.version);

  /// 期望的版本令牌。
  final String version;
}

/// 写入操作类型。
enum FsWriteOperation { create, update }

/// 整文件写入的结局。
class FsWriteOutcome {
  const FsWriteOutcome({
    required this.operation,
    required this.version,
    this.before,
    required this.after,
  });

  /// 新建还是覆盖。
  final FsWriteOperation operation;

  /// 写入后的版本令牌。
  final String version;

  /// 写入前的完整内容；新建或后端放弃提供时为 null。
  final String? before;

  /// 写入后的完整内容。
  final String after;
}

/// 字面替换的编辑请求。
class FsEditRequest {
  const FsEditRequest({
    required this.oldString,
    required this.newString,
    this.replaceAll = false,
  });

  /// 要替换的字面文本；非空，且必须精确匹配。
  final String oldString;

  /// 替换文本；空串表示删除匹配内容。
  final String newString;

  /// 替换全部匹配，而非要求恰好一处。
  final bool replaceAll;
}

/// 字面编辑的结局。
class FsEditOutcome {
  const FsEditOutcome({
    required this.version,
    required this.before,
    required this.after,
  });

  /// 编辑后的版本令牌。
  final String version;

  /// 编辑前的完整内容。
  final String before;

  /// 编辑后的完整内容。
  final String after;
}
