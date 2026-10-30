import 'package:conatus_foundation/conatus_foundation.dart';

/// 文本读取：分页、行号格式化、单行与总量截断。
class ReadFileText {
  const ReadFileText(
    this._fs, {
    this.defaultLimit = 2000,
    this.maxChars = 200000,
  });

  final FileSystem _fs;

  /// 默认读取行数上限。
  final int defaultLimit;

  /// 返回文本的最大字符数（超出截断）。
  final int maxChars;

  /// 读取 [target] 的文本并套用 `offset` / `limit` / `with_line_numbers`。
  Future<ToolResult> read(
    ToolContext ctx,
    FsTarget target,
    String path,
    String version,
  ) async {
    final List<String> lines = (await _fs.readText(target)).split('\n');
    final int total = lines.length;
    final int offset = (ctx.optional<int>('offset') ?? 1).clamp(1, total);
    final int limit = ctx.optional<int>('limit') ?? defaultLimit;
    final int end = (offset + limit - 1).clamp(offset, total);
    final bool withNumbers = ctx.optional<bool>('with_line_numbers') ?? true;
    final String body =
        _format(lines.sublist(offset - 1, end), offset, withNumbers);
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
      'version': version,
    });
  }

  /// 拼接读取片段；带行号时每行前缀 `%6d\t`（对齐 DSH）。
  /// 单行超过 2000 字符时截断并标记，避免一行占满上下文。
  String _format(List<String> lines, int startLine, bool withNumbers) {
    final List<String> clipped = <String>[
      for (final String line in lines) _clipLine(line),
    ];
    if (!withNumbers) return clipped.join('\n');
    final StringBuffer buffer = StringBuffer();
    for (var i = 0; i < clipped.length; i++) {
      buffer.writeln(
        '${(startLine + i).toString().padLeft(6)}\t${clipped[i]}',
      );
    }
    return buffer.toString();
  }

  String _clipLine(String line) {
    const int max = 2000;
    if (line.length <= max) return line;
    final Runes runes = line.runes;
    if (runes.length <= max) return line;
    return '${String.fromCharCodes(runes.take(max))}…';
  }
}
