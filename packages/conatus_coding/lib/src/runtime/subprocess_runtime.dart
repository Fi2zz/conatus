/// 子进程后端：把代码写入临时文件，经 `shell` 接缝执行。
///
/// 失败是结果字段（超时 / 非零退出 / 输出截断），不抛异常。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';
import 'code_run_request.dart';
import 'code_run_result.dart';
import 'code_runtime.dart';

/// 子进程代码执行后端。
class SubprocessCodeRuntime implements CodeRuntime {
  SubprocessCodeRuntime({
    required ShellExecutor shell,
    required this.executable,
    required this.extension,
    this.baseArgs = const <String>[],
    this.workingDirectory,
  }) : _shell = shell;

  final ShellExecutor _shell;

  /// 当前执行中的取消信号；单实例串行执行假设下只有一个活跃 run。
  Completer<void>? _cancel;

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
    final Completer<void> cancel = Completer<void>();
    _cancel = cancel;
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
        cancelSignal: cancel.future,
      ));
      final ShellRunResult result = await _shell.run(spec);
      if (cancel.isCompleted) {
        return CodeRunResult.failure(CodeRunFailureKind.abort, '执行已取消');
      }
      return _mapResult(result);
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
      await tmp.delete(recursive: true);
    }
  }

  /// 终止当前执行中的程序。幂等；无活跃执行时 no-op。
  @override
  Future<void> cancelCurrent() async {
    _cancel?.complete();
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
