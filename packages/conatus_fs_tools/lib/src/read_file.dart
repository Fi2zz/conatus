import 'package:conatus_foundation/conatus_foundation.dart';

import 'read_file_attachments.dart';
import 'read_file_directory.dart';
import 'read_file_text.dart';

/// 读取文件内容的工具。支持分页（offset / limit），默认带行号。
///
/// 图片（png / jpg / gif / webp）以 [ToolImage] 附件返回，模型可直接看到；
/// 其它二进制文件仍按文本读取并交给 fs 层报 `notText`。
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
  String get name => 'read';

  @override
  String get description =>
      '读取文件或目录；文本支持分页（offset / limit），图片/PDF 返回附件，单行超 2000 字符会截断。';

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
      if (info.type == FsFileType.directory) {
        return ReadFileDirectory(_fs).read(target, path);
      }
      if (info.type != FsFileType.file) {
        return _error('FS_NOT_REGULAR_FILE', '不是普通文件："$path"');
      }
      final String? imageMime = ReadFileAttachments.imageMime(path);
      if (imageMime != null) {
        return ReadFileAttachments(_fs).readImage(target, imageMime, path);
      }
      if (path.toLowerCase().endsWith('.pdf')) {
        return ReadFileAttachments(_fs).readPdf(target, path);
      }
      return ReadFileText(_fs, defaultLimit: defaultLimit, maxChars: maxChars)
          .read(ctx, target, path, info.version);
    } on FsError catch (e) {
      return _error(e.code.code, e.message);
    }
  }

  ToolResult _error(String code, String message) =>
      ToolResult.failure(message, error: ToolError(code, message));
}
