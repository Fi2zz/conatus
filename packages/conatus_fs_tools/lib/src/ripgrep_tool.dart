import 'package:conatus_foundation/conatus_foundation.dart';

import 'ripgrep_binary.dart';
import 'ripgrep_runner.dart';

/// grep 工具的运行限制。
class RipgrepLimits {
  const RipgrepLimits({
    this.defaultLimit = 50,
    this.maxMatches = 1000,
    this.timeout = const Duration(seconds: 20),
    this.maxOutputBytes = 20 * 1024 * 1024,
  });

  /// 默认结果数上限（每文件）。
  final int defaultLimit;

  /// 全局匹配数硬上限，超出即截断。
  final int maxMatches;

  /// 单次搜索超时。
  final Duration timeout;

  /// 输出采集字节上限。
  final int maxOutputBytes;
}

/// 在文件中搜索内容的工具：调用原生 ripgrep，返回其文本输出。
///
/// 命令经 [RipgrepRunner] 接缝落到目标环境（本地进程 / shell / 远程沙箱），
/// 不在工具内拼接 shell 命令。结果超上限时经 [ToolResultEviction] 落盘。
class RipgrepTool extends Tool {
  const RipgrepTool({
    required RipgrepRunner runner,
    required RipgrepBinary binary,
    this.eviction,
    this.limits = const RipgrepLimits(),
  })  : _runner = runner,
        _binary = binary;

  final RipgrepRunner _runner;
  final RipgrepBinary _binary;

  /// 截断时把完整输出落盘的驱逐器（可选）。
  final ToolResultEviction? eviction;

  /// 运行限制。
  final RipgrepLimits limits;

  @override
  String get name => 'grep';

  @override
  String get description => '在文件中搜索内容（原生 ripgrep）。默认忽略 .gitignore，结果超上限时落盘。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  Duration? get timeout => limits.timeout;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('pattern', required: true, description: '搜索模式（正则）'),
        ParamSpec.string('path', description: '搜索路径，默认当前目录'),
        ParamSpec.string('type', description: '文件类型过滤，如 dart / py / js'),
        ParamSpec.integer('context', description: '上下文行数'),
        ParamSpec.integer('limit',
            description: '结果数上限，默认 ${limits.defaultLimit}'),
        ParamSpec.boolean('files_only', description: '只返回文件名'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final bool filesOnly = ctx.optional<bool>('files_only') ?? false;
    final RipgrepRunResult result = await _runner.run(
      _binary,
      _args(ctx, filesOnly),
      timeout: limits.timeout,
      maxOutputBytes: limits.maxOutputBytes,
    );
    if (result.timedOut) {
      return _error('RG_TIMEOUT', 'rg 执行超时');
    }
    // exitCode == 1 表示无匹配，不是错误。
    if (result.exitCode == 1) {
      return ToolResult.success('无匹配',
          value: <String, Object?>{'truncated': false});
    }
    if (result.exitCode != 0) {
      return _error('RG_ERROR', 'rg 执行失败：${result.stderr}');
    }
    return _success(result.stdout);
  }

  /// 组装参数：pattern 与 path 一律放在 `--` 之后，避免被当成 flag。
  List<String> _args(ToolContext ctx, bool filesOnly) => <String>[
        '--max-count',
        '${ctx.optional<int>('limit') ?? limits.defaultLimit}',
        if (ctx.has('type')) ...<String>['--type', ctx.str('type')],
        if (ctx.has('context')) ...<String>['-C', '${ctx.integer('context')}'],
        if (filesOnly) '--files-with-matches',
        '--',
        ctx.str('pattern'),
        if (ctx.has('path')) ctx.str('path'),
      ];

  /// 透传原生 rg 的文本输出；行数达硬上限时判定截断并落盘。
  Future<ToolResult> _success(String stdout) async {
    final String text = stdout.trimRight();
    final bool truncated =
        text.isEmpty ? false : _lineCount(text) >= limits.maxMatches;
    final String? preview =
        truncated && eviction != null ? await eviction!.evict(text) : null;
    return ToolResult.success(
      preview ?? text,
      value: <String, Object?>{
        'truncated': truncated,
        if (preview != null) 'spilled': true,
        if (preview != null) 'spillPath': eviction!.spilledPaths.last,
        if (preview != null) 'note': '结果已截断，完整输出已落盘，可用 read 读取',
      },
    );
  }

  int _lineCount(String text) {
    var count = 1;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0a) count++;
    }
    return count;
  }

  ToolResult _error(String code, String message) =>
      ToolResult.failure(message, error: ToolError(code, message));
}
