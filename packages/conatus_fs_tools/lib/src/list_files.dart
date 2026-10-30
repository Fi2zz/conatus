import 'package:conatus_foundation/conatus_foundation.dart';

import 'fs_tools.dart';

/// `list` 的深度与条目数上限。
class ListLimits {
  const ListLimits({
    this.defaultDepth = 1,
    this.maxDepth = 5,
    this.defaultLimit = 200,
  });

  /// 默认展开深度。
  final int defaultDepth;

  /// 深度硬上限。
  final int maxDepth;

  /// 默认条目数上限。
  final int defaultLimit;
}

/// 列出目录内容的工具：按深度展开，目录以 `/` 结尾。
///
/// 走 `'fs'` 接缝，因此与 read / glob 受同一套路径约束；符号链接目录不跟随。
class ListFilesTool extends Tool {
  const ListFilesTool({
    required FileSystem fs,
    this.limits = const ListLimits(),
    this.skipDirs = kDefaultSkipDirs,
  }) : _fs = fs;

  final FileSystem _fs;

  /// 深度与条目数上限。
  final ListLimits limits;

  /// 递归时跳过的目录（按 basename），与 [GlobTool] 保持一致。
  final Set<String> skipDirs;

  @override
  String get name => 'list';

  @override
  String get description => '列出目录内容（目录以 / 结尾）。递归时跳过依赖 / 构建目录。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<String> get pathParams => const <String>['path'];

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('path', description: '目录路径，默认当前目录'),
        ParamSpec.integer('depth',
            description:
                '展开深度，默认 ${limits.defaultDepth}，上限 ${limits.maxDepth}'),
        ParamSpec.integer('limit',
            description: '条目数上限，默认 ${limits.defaultLimit}'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final int depth = (ctx.optional<int>('depth') ?? limits.defaultDepth)
        .clamp(1, limits.maxDepth);
    final int limit = ctx.optional<int>('limit') ?? limits.defaultLimit;
    final List<String> lines = <String>[];
    try {
      final FsTarget root =
          await _fs.resolve(ctx.optional<String>('path') ?? '.');
      await _walk(root, depth, _WalkState(limit, lines));
    } on FsError catch (e) {
      return ToolResult.failure(e.message,
          error: ToolError(e.code.code, e.message));
    }
    return ToolResult.success(
      lines.isEmpty ? '（空目录）' : lines.join('\n'),
      value: <String, Object?>{
        'entries': lines,
        'truncated': lines.length >= limit,
      },
    );
  }

  Future<void> _walk(FsTarget dir, int depth, _WalkState state) async {
    if (depth < 1) return;
    for (final FsDirEntry entry in await _fs.listDir(dir)) {
      if (state.out.length >= state.limit) return;
      if (_skipped(entry)) continue;
      final bool isDir = entry.type == FsFileType.directory;
      state.out.add('${state.prefix}${entry.name}${isDir ? '/' : ''}');
      if (!isDir) continue;
      if (await _symlinked(entry.target)) continue;
      final String saved = state.prefix;
      state.prefix = '$saved${entry.name}/';
      await _walk(entry.target, depth - 1, state);
      state.prefix = saved;
    }
  }

  bool _skipped(FsDirEntry entry) =>
      entry.type == FsFileType.directory && skipDirs.contains(entry.name);

  /// 不跟随符号链接目录：目标类型会被 `stat` 解析成 directory，需用 `lstat` 判定。
  Future<bool> _symlinked(FsTarget target) async {
    final FsPathInfo? info = await _fs.lstat(target.targetKey);
    return info?.type == FsFileType.symlink;
  }
}

/// 一次展开的游标：条目上限、输出与当前前缀。
class _WalkState {
  _WalkState(this.limit, this.out);

  final int limit;
  final List<String> out;
  String prefix = '';
}
