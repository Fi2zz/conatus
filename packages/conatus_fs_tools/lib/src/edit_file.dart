import 'package:conatus_foundation/conatus_foundation.dart';

/// 编辑文件的工具。默认要求 old_string 唯一匹配，replace_all 可替换所有匹配。
class EditFileTool extends Tool {
  const EditFileTool({required FileSystem fs}) : _fs = fs;

  final FileSystem _fs;

  @override
  String get name => 'edit_file';

  @override
  String get description =>
      '编辑文件。默认要求 old_string 唯一匹配，replace_all 可替换所有匹配。';

  @override
  ToolRisk get riskLevel => ToolRisk.medium;

  @override
  List<String> get pathParams => const <String>['path'];

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('path', required: true, description: '文件路径'),
        ParamSpec.string('old_string', required: true, description: '被替换的字符串'),
        ParamSpec.string('new_string', required: true, description: '替换成的字符串'),
        ParamSpec.boolean('replace_all', description: '是否替换所有匹配，默认 false'),
        ParamSpec.string('expected_version', description: '期望的文件版本，用于版本守卫'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String path = ctx.str('path');
    final String oldString = ctx.str('old_string');
    final String newString = ctx.str('new_string');
    final bool replaceAll = ctx.optional<bool>('replace_all') ?? false;
    try {
      final FsTarget target = await _fs.resolve(path);
      if (oldString == newString) {
        return _error('FS_NO_CHANGE', 'old_string 与 new_string 相同');
      }
      final String raw = await _fs.readText(target);
      final int matches = oldString.allMatches(raw).length;
      if (matches == 0) {
        return _error('FS_NOT_FOUND', '未找到 old_string');
      }
      if (matches > 1 && !replaceAll) {
        return _error(
          'FS_AMBIGUOUS_EDIT',
          'old_string 匹配 $matches 处，需用 replace_all 或提供更多上下文',
        );
      }
      await _fs.editText(
        target,
        FsEditRequest(
          oldString: oldString,
          newString: newString,
          replaceAll: replaceAll,
        ),
        expectedVersion: ctx.optional<String>('expected_version'),
      );
      final FsInfo? info = await _fs.stat(target);
      return ToolResult.success('已编辑 "$path"', value: <String, Object?>{
        'path': target.displayPath,
        'replacements': replaceAll ? matches : 1,
        'version': info?.version,
      });
    } on FsError catch (e) {
      return ToolResult.failure(e.message, error: ToolError(e.code.code, e.message));
    }
  }

  ToolResult _error(String code, String message) =>
      ToolResult.failure(message, error: ToolError(code, message));
}
