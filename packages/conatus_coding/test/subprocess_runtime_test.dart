import 'dart:async';
import 'dart:io';

import 'package:conatus_coding/conatus_coding.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

import 'support/fake_shell.dart';

ShellRunResult _run({
  int? exitCode,
  bool timedOut = false,
  String stdout = '',
  String stderr = '',
  bool stdoutTruncated = false,
}) =>
    ShellRunResult(
      exitCode: exitCode,
      timedOut: timedOut,
      timeoutMs: 30000,
      stdout: CollectedOutput(text: stdout, truncated: stdoutTruncated),
      stderr: CollectedOutput(text: stderr),
    );

SubprocessCodeRuntime _runtime(FakeShellExecutor shell) =>
    SubprocessCodeRuntime(
      shell: shell,
      executable: 'dart',
      extension: '.dart',
    );

List<Directory> _tempDirs(String prefix) => Directory.systemTemp
    .listSync()
    .whereType<Directory>()
    .where((Directory d) => d.path.contains(prefix))
    .toList();

void main() {
  group('SubprocessCodeRuntime', () {
    test('成功 → success，value 为 stdout，logs 为 stderr 按行拆分', () async {
      final FakeShellExecutor shell = FakeShellExecutor(
          _run(exitCode: 0, stdout: 'hello\n', stderr: 'warn\nlog\n'));

      final CodeRunResult result =
          await _runtime(shell).run(const CodeRunRequest(program: 'print(1)'));

      expect(result.isSuccess, isTrue);
      expect(result.value, 'hello\n');
      expect(result.logs, <String>['warn', 'log']);
    });

    test('非零退出 → exception，message 为 stderr', () async {
      final FakeShellExecutor shell =
          FakeShellExecutor(_run(exitCode: 2, stderr: 'boom'));

      final CodeRunResult result =
          await _runtime(shell).run(const CodeRunRequest(program: 'x'));

      expect(result.isSuccess, isFalse);
      expect(result.error!.kind, CodeRunFailureKind.exception);
      expect(result.error!.message, 'boom');
    });

    test('超时 → timeout', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_run(timedOut: true));

      final CodeRunResult result =
          await _runtime(shell).run(const CodeRunRequest(program: 'x'));

      expect(result.error!.kind, CodeRunFailureKind.timeout);
    });

    test('输出截断 → outputLimit', () async {
      final FakeShellExecutor shell =
          FakeShellExecutor(_run(exitCode: 0, stdoutTruncated: true));

      final CodeRunResult result =
          await _runtime(shell).run(const CodeRunRequest(program: 'x'));

      expect(result.error!.kind, CodeRunFailureKind.outputLimit);
    });

    test('默认限制 → timeoutMs 30000 / stdoutMaxBytes 1MB', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_run(exitCode: 0));

      await _runtime(shell).run(const CodeRunRequest(program: 'x'));

      expect(shell.lastRequest!.timeoutMs, 30000);
      expect(shell.lastRequest!.stdoutMaxBytes, 1024 * 1024);
    });

    test('请求携带 cancelSignal', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_run(exitCode: 0));

      await _runtime(shell).run(const CodeRunRequest(program: 'x'));

      expect(shell.lastRequest!.cancelSignal, isNotNull);
    });

    test('cancelCurrent → 返回 abort 失败', () async {
      final Completer<void> gate = Completer<void>();
      final FakeShellExecutor shell =
          FakeShellExecutor(_run(exitCode: 0), gate);
      final SubprocessCodeRuntime runtime = _runtime(shell);

      final Future<CodeRunResult> pending =
          runtime.run(const CodeRunRequest(program: 'x'));
      await runtime.cancelCurrent();
      gate.complete();

      final CodeRunResult result = await pending;

      expect(result.error!.kind, CodeRunFailureKind.abort);
    });

    test('无活跃执行时 cancelCurrent 是 no-op', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_run(exitCode: 0));
      final SubprocessCodeRuntime runtime = _runtime(shell);

      await runtime.cancelCurrent();

      final CodeRunResult result =
          await runtime.run(const CodeRunRequest(program: 'x'));
      expect(result.isSuccess, isTrue);
    });

    test('request.timeout 覆盖默认限制', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_run(exitCode: 0));

      await _runtime(shell).run(
          const CodeRunRequest(program: 'x', timeout: Duration(seconds: 5)));

      expect(shell.lastRequest!.timeoutMs, 5000);
    });

    test('命令构造：引号化 executable + baseArgs + 临时文件路径', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_run(exitCode: 0));

      await SubprocessCodeRuntime(
        shell: shell,
        executable: 'dart',
        extension: '.dart',
        baseArgs: const <String>['run'],
        workingDirectory: '/tmp/wd',
      ).run(const CodeRunRequest(program: 'main() {}'));

      final String command = shell.lastRequest!.command;
      expect(command.startsWith("'dart' 'run' '"), isTrue);
      expect(command.endsWith('program.dart\''), isTrue);
      expect(shell.lastRequest!.workdir, '/tmp/wd');
    });

    test('language 由 extension 推断', () {
      expect(
        SubprocessCodeRuntime(
          shell: FakeShellExecutor(),
          executable: 'dart',
          extension: '.dart',
        ).language,
        'dart',
      );
      expect(
        SubprocessCodeRuntime(
          shell: FakeShellExecutor(),
          executable: 'python3',
          extension: '.py',
        ).language,
        'python',
      );
    });

    test('临时目录在执行后被清理', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_run(exitCode: 0));
      final int before = _tempDirs('conatus-code-').length;

      await _runtime(shell).run(const CodeRunRequest(program: 'x'));

      expect(_tempDirs('conatus-code-').length, before);
    });
  });
}
