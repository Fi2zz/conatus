import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:glob/glob.dart';

/// 按 glob 模式发现文件的工具。
class GlobTool extends Tool {
  const GlobTool({required FileSystem fs, this.defaultLimit = 100}) : _fs = fs;

  final FileSystem _fs;

  /// 默认结果数上限。
  final int defaultLimit;

  /// 遍历时跳过的目录（按 basename）。
  static const Set<String> _skipDirs =
      <String>{'.git', 'node_modules', '.dart_tool', 'build'};

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
        ParamSpec.string('pattern', required: true, description: 'glob 模式，如 **/*.dart'),
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
      final FsTarget root = await _fs.resolve(ctx.optional<String>('path') ?? '.');
      final List<String> matches = <String>[];
      await _walk(root, glob, matches, limit, const <String>[]);
      return ToolResult.success(matches.join('\n'), value: <String, Object?>{
        'pattern': pattern,
        'matches': matches,
        'truncated': matches.length >= limit,
      });
    } on FsError catch (e) {
      return ToolResult.failure(e.message, error: ToolError(e.code.code, e.message));
    }
  }

  Future<void> _walk(
    FsTarget dir,
    Glob glob,
    List<String> out,
    int limit,
    List<String> rel,
  ) async {
    if (out.length >= limit) return;
    final List<FsDirEntry> entries = await _fs.listDir(dir);
    for (final FsDirEntry entry in entries) {
      if (out.length >= limit) return;
      if (entry.type == FsFileType.directory) {
        if (_skipDirs.contains(entry.name)) continue;
        await _walk(entry.target, glob, out, limit, <String>[...rel, entry.name]);
      } else if (entry.type == FsFileType.file &&
          glob.matches(<String>[...rel, entry.name].join('/'))) {
        out.add(entry.target.displayPath);
      }
    }
  }

  ToolResult _error(String code, String message) =>
      ToolResult.failure(message, error: ToolError(code, message));
}
