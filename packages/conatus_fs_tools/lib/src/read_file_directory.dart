import 'package:conatus_foundation/conatus_foundation.dart';

/// 目录列举（非递归）：OpenCode `read` 的目录行为。
class ReadFileDirectory {
  const ReadFileDirectory(this._fs);

  final FileSystem _fs;

  /// 列出 [target] 的直接子项，目录带 `/` 后缀。
  Future<ToolResult> read(FsTarget target, String path) async {
    final List<FsDirEntry> entries = await _fs.listDir(target);
    entries.sort((FsDirEntry a, FsDirEntry b) => a.name.compareTo(b.name));
    final StringBuffer buffer = StringBuffer(
      '目录 "$path"（${entries.length} 项）：\n',
    );
    for (final FsDirEntry entry in entries) {
      final String mark = switch (entry.type) {
        FsFileType.directory => 'd',
        FsFileType.symlink => 'l',
        FsFileType.file => 'f',
        FsFileType.other => '?',
      };
      buffer.writeln(
        '$mark ${entry.name}${entry.type == FsFileType.directory ? '/' : ''}',
      );
    }
    return ToolResult.success(
      buffer.toString(),
      value: <String, Object?>{
        'path': target.displayPath,
        'type': 'directory',
        'entries': <Map<String, Object?>>[
          for (final FsDirEntry entry in entries)
            <String, Object?>{
              'name': entry.name,
              'type': entry.type.name,
              if (entry.size != null) 'size': entry.size,
            },
        ],
      },
    );
  }
}
