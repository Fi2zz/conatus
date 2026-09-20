/// fs 工具：把文件系统能力缝暴露给模型。
///
/// [ReadFileTool] 走 `ctx.fs` 读文本；[provideFsTools] 一次性注册到 `ctx.tools`。
/// 工具结果驱逐（`tool_result_eviction.dart`）落盘的大结果即由它读回。
library;

import 'package:conatus_core/conatus_core.dart';
import 'fs.dart';
import 'tools.dart';

/// 读取本地文件文本的工具。
class ReadFileTool extends Tool {
  ReadFileTool({required FileSystem fs, this.maxChars = 100000}) : _fs = fs;

  final FileSystem _fs;

  /// 返回文本的最大字符数（超出截断）。
  final int maxChars;

  @override
  String get name => 'read_file';

  @override
  String get description => '读取一个本地文件并返回其文本内容。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<String> get pathParams => const <String>['path'];

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('path', required: true, description: '文件路径'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String path = ctx.str('path');
    try {
      final FsTarget target = await _fs.resolve(path);
      final FsInfo? info = await _fs.stat(target);
      if (info == null) {
        return ToolResult.failure(
          '文件不存在："$path"',
          error: const ToolError('FS_NOT_FOUND', 'file not found'),
        );
      }
      if (info.type != FsFileType.file) {
        return ToolResult.failure(
          '不是普通文件："$path"',
          error: const ToolError('FS_NOT_REGULAR_FILE', 'not a regular file'),
        );
      }
      final String content = await _fs.readText(target);
      final String clipped =
          content.length > maxChars ? content.substring(0, maxChars) : content;
      return ToolResult.success(
        clipped,
        value: <String, Object?>{
          'path': target.displayPath,
          'chars': content.length,
          'truncated': clipped.length < content.length,
        },
      );
    } on FsError catch (error) {
      return ToolResult.failure(
        '读取失败：${error.message}',
        error: ToolError(error.code.code, error.message),
      );
    }
  }
}

/// 把 fs 工具注册到 `ctx.tools`，返回已注册的工具。
///
/// [fs] 缺省取上下文的 `'fs'` 服务；[tools] 缺省取 `ctx.tools`。
List<Tool> provideFsTools(
  Context ctx, {
  FileSystem? fs,
  ToolRegistry? tools,
}) {
  final FileSystem resolved = fs ?? ctx.require<FileSystem>('fs');
  final ToolRegistry registry = tools ?? ctx.tools;
  final List<Tool> registered = <Tool>[ReadFileTool(fs: resolved)];
  for (final Tool tool in registered) {
    ctx.effect(() => registry.register(tool));
  }
  return registered;
}
