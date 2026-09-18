/// 假 Shell 执行器：按命令前缀返回预设输出，记录调用。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

class FakeShellExecutor implements ShellExecutor {
  final Map<String, String> _stdout = <String, String>{};

  /// 视为失败的命令前缀（返回退出码 1）。
  final Set<String> failingPrefixes = <String>{};

  /// 记录所有被 [run] 的命令。
  final List<String> commands = <String>[];

  /// 预设命令前缀 → stdout 文本。
  void stub(String prefix, String stdout) => _stdout[prefix] = stdout;

  @override
  ShellExecSpec resolve(ShellExecRequest request) => ShellExecSpec(
        command: request.command,
        workdir: request.workdir ?? '/tmp',
        timeoutMs: request.timeoutMs ?? 30000,
        stdoutMaxBytes: request.stdoutMaxBytes ?? 1 << 20,
        stdin: request.stdin,
        env: request.env,
      );

  @override
  Future<ShellRunResult> run(ShellExecSpec spec) async {
    commands.add(spec.command);
    final String? output = _match(spec.command);
    final bool failed = failingPrefixes.any(spec.command.startsWith);
    return ShellRunResult(
      exitCode: failed ? 1 : 0,
      timedOut: false,
      timeoutMs: spec.timeoutMs,
      stdout: CollectedOutput(text: output ?? (failed ? '' : 'ok')),
      stderr: CollectedOutput(text: failed ? 'error' : ''),
    );
  }

  @override
  Future<ShellProcess> start(ShellExecSpec spec) async {
    throw UnsupportedError('集成测试不使用后台 shell 进程');
  }

  String? _match(String command) {
    for (final MapEntry<String, String> entry in _stdout.entries) {
      if (command.startsWith(entry.key)) return entry.value;
    }
    return null;
  }
}
