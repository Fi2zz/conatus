import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:glob/glob.dart';

import 'fs_tools.dart';

/// 按 glob 模式发现文件的工具。符号链接目录不跟随。
class GlobTool extends Tool {
  const GlobTool({
    required FileSystem fs,
    this.defaultLimit = 100,
    this.skipDirs = kDefaultSkipDirs,
  }) : _fs = fs;

  final FileSystem _fs;

  /// 默认结果数上限。
  final int defaultLimit;

  /// 遍历时跳过的目录（按 basename）。
  final Set<String> skipDirs;

  @override
  String get name => 'glob';

  @override
  String get description => '按 glob 模式发现文件。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<String> get pathParams => const <String>['path'];

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('pattern',
            required: true, description: 'glob 模式，如 **/*.dart'),
        ParamSpec.string('path', description: '搜索根目录，默认当前目录'),
        ParamSpec.integer('limit', description: '结果数上限，默认 $defaultLimit'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String pattern = ctx.str('pattern');
    final int limit = ctx.optional<int>('limit') ?? defaultLimit;
    final Glob glob;
    try {
      glob = Glob(pattern);
    } on FormatException {
      return _error('GLOB_INVALID_PATTERN', '无效的 glob 模式：$pattern');
    }
    try {
      final FsTarget root =
          await _fs.resolve(ctx.optional<String>('path') ?? '.');
      final _GlobWalk walk = _GlobWalk(glob, limit);
      await _walk(root, walk);
      return ToolResult.success(walk.matches.join('\n'),
          value: <String, Object?>{
            'pattern': pattern,
            'matches': walk.matches,
            'truncated': walk.matches.length >= limit,
          });
    } on FsError catch (e) {
      return ToolResult.failure(e.message,
          error: ToolError(e.code.code, e.message));
    }
  }

  Future<void> _walk(FsTarget dir, _GlobWalk walk) async {
    if (walk.matches.length >= walk.limit) return;
    final List<FsDirEntry> entries = await _fs.listDir(dir);
    for (final FsDirEntry entry in entries) {
      if (walk.matches.length >= walk.limit) return;
      if (entry.type == FsFileType.directory) {
        if (skipDirs.contains(entry.name)) continue;
        if (await _symlinked(entry.target)) continue;
        walk.rel.add(entry.name);
        await _walk(entry.target, walk);
        walk.rel.removeLast();
      } else if (entry.type == FsFileType.file &&
          walk.glob.matches(<String>[...walk.rel, entry.name].join('/'))) {
        walk.matches.add(entry.target.displayPath);
      }
    }
  }

  /// 不跟随符号链接目录：目标类型会被 `stat` 解析成 directory，需用 `lstat` 判定。
  Future<bool> _symlinked(FsTarget target) async {
    final FsPathInfo? info = await _fs.lstat(target.targetKey);
    return info?.type == FsFileType.symlink;
  }

  ToolResult _error(String code, String message) =>
      ToolResult.failure(message, error: ToolError(code, message));
}

/// 一次遍历的游标：模式、结果上限与当前相对路径。
class _GlobWalk {
  _GlobWalk(this.glob, this.limit);

  final Glob glob;
  final int limit;
  final List<String> matches = <String>[];
  final List<String> rel = <String>[];
}
