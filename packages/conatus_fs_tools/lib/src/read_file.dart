import 'package:conatus_foundation/conatus_foundation.dart';

/// 读取文件内容的工具。支持分页（offset / limit），默认带行号。
class ReadFileTool extends Tool {
  const ReadFileTool({
    required FileSystem fs,
    this.defaultLimit = 2000,
    this.maxChars = 200000,
  }) : _fs = fs;

  final FileSystem _fs;

  /// 默认读取行数上限。
  final int defaultLimit;

  /// 返回文本的最大字符数（超出截断）。
  final int maxChars;

  @override
  String get name => 'read_file';

  @override
  String get description => '读取文件内容。支持分页（offset / limit），默认带行号。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<String> get pathParams => const <String>['path'];

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('path', required: true, description: '文件路径'),
        ParamSpec.integer('offset', description: '起始行号（1-based），默认 1'),
        ParamSpec.integer('limit', description: '读取行数上限，默认 $defaultLimit'),
        ParamSpec.boolean('with_line_numbers', description: '是否带行号，默认 true'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String path = ctx.str('path');
    try {
      final FsTarget target = await _fs.resolve(path);
      final FsInfo? info = await _fs.stat(target);
      if (info == null) {
        return _error('FS_NOT_FOUND', '文件不存在："$path"');
      }
      if (info.type != FsFileType.file) {
        return _error('FS_NOT_REGULAR_FILE', '不是普通文件："$path"');
      }
      final List<String> lines = (await _fs.readText(target)).split('\n');
      final int total = lines.length;
      final int offset = (ctx.optional<int>('offset') ?? 1).clamp(1, total);
      final int limit = ctx.optional<int>('limit') ?? defaultLimit;
      final int end = (offset + limit - 1).clamp(offset, total);
      final bool withNumbers = ctx.optional<bool>('with_line_numbers') ?? true;
      final String body = _format(lines.sublist(offset - 1, end), offset, withNumbers);
      final bool truncated = end < total || body.length > maxChars;
      final String content = body.length > maxChars
          ? '${body.substring(0, maxChars)}\n...(截断)'
          : body;
      return ToolResult.success(content, value: <String, Object?>{
        'path': target.displayPath,
        'startLine': offset,
        'endLine': end,
        'totalLines': total,
        'truncated': truncated,
        'version': info.version,
      });
    } on FsError catch (e) {
      return _error(e.code.code, e.message);
    }
  }

  /// 拼接读取片段；带行号时每行前缀 `%6d\t`（对齐 DSH）。
  String _format(List<String> lines, int startLine, bool withNumbers) {
    if (!withNumbers) return lines.join('\n');
    final StringBuffer buffer = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      buffer.writeln('${(startLine + i).toString().padLeft(6)}\t${lines[i]}');
    }
    return buffer.toString();
  }

  ToolResult _error(String code, String message) =>
      ToolResult.failure(message, error: ToolError(code, message));
}
