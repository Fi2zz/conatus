import 'package:conatus_foundation/conatus_foundation.dart';

/// 写入模式。
enum WriteMode {
  /// 创建。文件已存在则失败。
  create,

  /// 覆盖。文件不存在则创建。
  overwrite,

  /// 追加。
  append,
}

/// 写入文件的工具。create 要求文件不存在，overwrite 覆盖，append 追加。
class WriteFileTool extends Tool {
  const WriteFileTool({required FileSystem fs}) : _fs = fs;

  final FileSystem _fs;

  @override
  String get name => 'write_file';

  @override
  String get description =>
      '写入文件。create 模式要求文件不存在，overwrite 模式覆盖，append 模式追加。';

  @override
  ToolRisk get riskLevel => ToolRisk.medium;

  @override
  List<String> get pathParams => const <String>['path'];

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('path', required: true, description: '文件路径'),
        ParamSpec.string('content', required: true, description: '文件内容'),
        ParamSpec.enumeration(
          'mode',
          const <String>['create', 'overwrite', 'append'],
          description: '写入模式，默认 create',
        ),
        ParamSpec.string('expected_version', description: '期望的文件版本，用于覆盖守卫'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String path = ctx.str('path');
    final String content = ctx.str('content');
    try {
      final FsTarget target = await _fs.resolve(path);
      final WriteMode mode = _parseMode(ctx.optional<String>('mode'));
      if (mode == WriteMode.append) {
        await _fs.writeText(target, await _readExisting(target) + content);
      } else {
        await _fs.writeText(target, content, expected: _guard(mode, ctx));
      }
      final FsInfo? info = await _fs.stat(target);
      return ToolResult.success('已写入 "$path"', value: <String, Object?>{
        'path': target.displayPath,
        'mode': mode.name,
        'bytes': content.length,
        'version': info?.version,
      });
    } on FsError catch (e) {
      return ToolResult.failure(e.message, error: ToolError(e.code.code, e.message));
    }
  }

  WriteMode _parseMode(String? name) => switch (name) {
        'overwrite' => WriteMode.overwrite,
        'append' => WriteMode.append,
        _ => WriteMode.create,
      };

  FsWriteIntent? _guard(WriteMode mode, ToolContext ctx) => switch (mode) {
        WriteMode.create => const FsCreateIfAbsent(),
        WriteMode.overwrite when ctx.has('expected_version') =>
          FsReplaceIfVersion(ctx.str('expected_version')),
        _ => null,
      };

  Future<String> _readExisting(FsTarget target) async {
    try {
      return await _fs.readText(target);
    } on FsError catch (e) {
      if (e.code == FsErrorCode.notFound) return '';
      rethrow;
    }
  }
}
