import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'ripgrep_binary.dart';

/// 在文件中搜索内容的工具：直接调用原生 ripgrep，返回其文本输出。
///
/// 经 `shell` 接缝子进程执行本机 rg，不自行解析或实现搜索。结果超上限时
/// 经 [ToolResultEviction] 落盘，模型按路径读回。
class RipgrepTool extends Tool {
  const RipgrepTool({
    required ShellExecutor shell,
    required RipgrepBinary binary,
    this.eviction,
    this.defaultLimit = 50,
    this.maxMatches = 1000,
    this.timeout = const Duration(seconds: 20),
  })  : _shell = shell,
        _binary = binary;

  final ShellExecutor _shell;
  final RipgrepBinary _binary;

  /// 截断时把完整输出落盘的驱逐器（可选）。
  final ToolResultEviction? eviction;

  /// 默认结果数上限（每文件）。
  final int defaultLimit;

  /// 全局匹配数硬上限，超出即截断。
  final int maxMatches;

  /// 单次搜索超时。
  @override
  final Duration? timeout;

  static const int _maxOutputBytes = 20 * 1024 * 1024;

  @override
  String get name => 'rg';

  @override
  String get description =>
      '在文件中搜索内容（原生 ripgrep）。默认忽略 .gitignore，结果超上限时落盘。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('pattern', required: true, description: '搜索模式（正则）'),
        ParamSpec.string('path', description: '搜索路径，默认当前目录'),
        ParamSpec.string('type', description: '文件类型过滤，如 dart / py / js'),
        ParamSpec.integer('context', description: '上下文行数'),
        ParamSpec.integer('limit', description: '结果数上限，默认 $defaultLimit'),
        ParamSpec.boolean('files_only', description: '只返回文件名'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final bool filesOnly = ctx.optional<bool>('files_only') ?? false;
    final ShellExecSpec spec = _shell.resolve(ShellExecRequest(
      command: _command(ctx, filesOnly),
      timeoutMs: timeout?.inMilliseconds ?? 0,
      stdoutMaxBytes: _maxOutputBytes,
    ));
    final ShellRunResult result = await _shell.run(spec);
    if (result.timedOut) {
      return _error('RG_TIMEOUT', 'rg 执行超时');
    }
    // exitCode == 1 表示无匹配，不是错误。
    if (result.exitCode == 1) {
      return ToolResult.success('无匹配',
          value: <String, Object?>{'truncated': false});
    }
    if (result.exitCode != 0) {
      return _error('RG_ERROR', 'rg 执行失败：${result.stderr.text}');
    }
    return _success(result.stdout.text);
  }

  String _command(ToolContext ctx, bool filesOnly) {
    final List<String> args = <String>[
      '--max-count', '${ctx.optional<int>('limit') ?? defaultLimit}',
      '--max-count-matches', '$maxMatches',
    ];
    if (ctx.has('type')) args.addAll(<String>['--type', ctx.str('type')]);
    if (ctx.has('context')) args.addAll(<String>['-C', '${ctx.integer('context')}']);
    if (filesOnly) args.add('--files-with-matches');
    args.add('--');
    args.add(ctx.str('pattern'));
    if (ctx.has('path')) args.add(ctx.str('path'));
    return <String>[_quote(_binary.path), ...args.map(_quote)].join(' ');
  }

  /// 透传原生 rg 的文本输出；行数达硬上限时判定截断并落盘。
  Future<ToolResult> _success(String stdout) async {
    final String text = stdout.trimRight();
    final bool truncated = text.isEmpty ? false : _lineCount(text) >= maxMatches;
    final String? preview =
        truncated && eviction != null ? await eviction!.evict(text) : null;
    return ToolResult.success(
      preview ?? text,
      value: <String, Object?>{
        'truncated': truncated,
        if (preview != null) 'spilled': true,
        if (preview != null) 'spillPath': eviction!.spilledPaths.last,
        if (preview != null)
          'note': '结果已截断，完整输出已落盘，可用 read_file 读取',
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

  String _quote(String s) => "'${s.replaceAll("'", "'\\''")}'";
}
