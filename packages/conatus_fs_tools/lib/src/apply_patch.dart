import 'package:conatus_diff/conatus_diff.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'opencode_patch.dart';
import 'opencode_patch_apply.dart';

/// 应用补丁的工具：支持统一格式（unified）diff 与 OpenCode / Codex
/// `*** Begin Patch` 两种格式。
///
/// 逐文件按 hunk 倒序应用：上下文行（' ' 与 '-' 前缀）必须与现有内容逐行
/// 相等，任一文件失败立即返回失败（已应用的其它文件不回滚，靠版本守卫兜底）。
class ApplyPatchTool extends Tool {
  const ApplyPatchTool({required FileSystem fs}) : _fs = fs;

  final FileSystem _fs;

  @override
  String get name => 'apply_patch';

  @override
  String get description => '应用 unified diff 或 OpenCode *** 补丁到文件。';

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string(
          'patch',
          required: true,
          description: 'unified diff 或 OpenCode *** 补丁文本',
        ),
      ];

  @override
  ToolRisk get riskLevel => ToolRisk.high;

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String patch = ctx.str('patch');
    if (_openCodePatch(patch)) return _applyOpenCode(patch);
    final List<FileDiff> files = parseUnifiedDiff(patch);
    if (files.isEmpty) {
      return ToolResult.failure(
        '无法解析 patch',
        error: const ToolError('PATCH_INVALID', '无法解析 patch'),
      );
    }
    final List<String> applied = <String>[];
    try {
      for (final FileDiff file in files) {
        if (!_applicable(file)) continue;
        await _applyFile(file);
        applied.add(file.path);
      }
    } on FsError catch (e) {
      return ToolResult.failure(
        e.message,
        error: ToolError(e.code.code, e.message),
      );
    } on PatchContextException catch (e) {
      return ToolResult.failure(
        e.message,
        error: ToolError('PATCH_CONTEXT', e.message),
      );
    }
    if (applied.isEmpty) {
      const String message = '补丁仅含二进制或文件元数据变更，无法应用';
      return ToolResult.failure(
        message,
        error: const ToolError('PATCH_UNSUPPORTED', message),
      );
    }
    return ToolResult.success(
      '已应用 ${applied.length} 个文件：${applied.join(', ')}',
      value: <String, Object?>{'files': applied, 'diff': patch},
    );
  }

  /// 应用 OpenCode / Codex `***` 补丁。
  Future<ToolResult> _applyOpenCode(String patch) async {
    final List<OpenCodePatchOp> ops;
    try {
      ops = parseOpenCodePatch(patch);
    } on FormatException catch (error) {
      return ToolResult.failure(
        '无法解析 patch：${error.message}',
        error: ToolError('PATCH_INVALID', error.message),
      );
    }
    final List<String> applied = <String>[];
    try {
      for (final OpenCodePatchOp op in ops) {
        await applyOpenCodeOps(_fs, <OpenCodePatchOp>[op]);
        applied.add(op.path);
      }
    } on OpenCodePatchException catch (error) {
      return ToolResult.failure(
        error.message,
        error: ToolError(error.code, error.message),
      );
    } on FsError catch (error) {
      return ToolResult.failure(
        error.message,
        error: ToolError(error.code.code, error.message),
      );
    }
    return ToolResult.success(
      '已应用 ${applied.length} 个文件：${applied.join(', ')}',
      value: <String, Object?>{'files': applied, 'diff': patch},
    );
  }

  /// 二进制 / 仅元数据变更没有可应用的 hunk；空文件新增（added + 无 hunk）
  /// 仍要物化，故不能一律跳过。
  bool _applicable(FileDiff file) {
    if (file.status == 'binary') return false;
    return file.hunks.isNotEmpty || file.status == 'added';
  }

  /// 应用单个文件（目标不存在视为空文件）；应用语义见 diff/apply.dart。
  Future<void> _applyFile(DiffFile file) async {
    final FsTarget target = await _fs.resolve(file.path);
    final String oldText = await _readTextOrEmpty(target);
    await _fs.writeText(target, applyDiffFile(oldText, file));
  }

  /// 读取旧内容；目标不存在视为空串，其它 [FsError] 上抛。
  Future<String> _readTextOrEmpty(FsTarget target) async {
    try {
      return await _fs.readText(target);
    } on FsError catch (e) {
      if (e.code == FsErrorCode.notFound) return '';
      rethrow;
    }
  }
}

/// OpenCode / Codex 的 `***` 补丁头；命中后走专用解析器。
const List<String> _openCodeMarkers = <String>[
  '*** Begin Patch',
  '*** Add File:',
  '*** Update File:',
  '*** Delete File:',
];

bool _openCodePatch(String patch) => _openCodeMarkers.any(patch.contains);
