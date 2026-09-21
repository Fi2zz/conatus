/// 子进程后端：把代码写入临时文件，经 `shell` 接缝执行。
///
/// 失败是结果字段（超时 / 非零退出 / 输出截断），不抛异常。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';
import 'code_run_request.dart';
import 'code_run_result.dart';
import 'code_runtime.dart';

/// 子进程代码执行后端。
class SubprocessCodeRuntime implements CodeRuntime {
  const SubprocessCodeRuntime({
    required ShellExecutor shell,
    required this.executable,
    required this.extension,
    this.baseArgs = const <String>[],
    this.workingDirectory,
  }) : _shell = shell;

  final ShellExecutor _shell;

  /// 可执行程序，如 'dart' / 'python3'。
  final String executable;

  /// 临时文件扩展名，如 '.dart' / '.py'。
  final String extension;

  /// 附加参数。
  final List<String> baseArgs;

  /// 工作目录。
  final String? workingDirectory;

  @override
  String get language => extension == '.dart' ? 'dart' : 'python';

  @override
  String get isolation => 'process';

  @override
  Future<CodeRunResult> run(CodeRunRequest request) async {
    final Directory tmp =
        await Directory.systemTemp.createTemp('conatus-code-');
    try {
      final File file = File('${tmp.path}/program$extension');
      await file.writeAsString(request.program);
      final CodeRunLimits limits = request.limits ?? const CodeRunLimits();
      final ShellExecSpec spec = _shell.resolve(ShellExecRequest(
        command: _command(file.path),
        workdir: workingDirectory,
        timeoutMs: (request.timeout ?? limits.maxDuration).inMilliseconds,
        stdoutMaxBytes: limits.maxOutputBytes,
      ));
      final ShellRunResult result = await _shell.run(spec);
      return _mapResult(result);
    } finally {
      await tmp.delete(recursive: true);
    }
  }

  @override
  void dispose() {}

  String _command(String filePath) => <String>[
        _quote(executable),
        ...baseArgs.map(_quote),
        _quote(filePath),
      ].join(' ');

  CodeRunResult _mapResult(ShellRunResult result) {
    if (result.timedOut) {
      return CodeRunResult.failure(CodeRunFailureKind.timeout, '执行超时');
    }
    if (result.stdout.truncated) {
      return CodeRunResult.failure(CodeRunFailureKind.outputLimit, '输出超出上限');
    }
    if (result.exitCode != 0) {
      return CodeRunResult.failure(
        CodeRunFailureKind.exception,
        result.stderr.text,
      );
    }
    return CodeRunResult.success(
      result.stdout.text,
      logs: const LineSplitter().convert(result.stderr.text),
    );
  }
}

String _quote(String s) => "'${s.replaceAll("'", "'\\''")}'";
