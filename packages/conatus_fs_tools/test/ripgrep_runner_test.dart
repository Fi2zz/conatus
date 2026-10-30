import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_fs_tools/conatus_fs_tools.dart';
import 'package:test/test.dart';

import 'support/fake_shell.dart';

const RipgrepBinary _rg =
    RipgrepBinary(path: 'rg', source: RipgrepSource.system);

ShellRunResult _shellResult({
  int? exitCode = 0,
  bool timedOut = false,
  String stdout = '',
  String stderr = '',
}) =>
    ShellRunResult(
      exitCode: exitCode,
      timedOut: timedOut,
      timeoutMs: 1000,
      stdout: CollectedOutput(text: stdout),
      stderr: CollectedOutput(text: stderr),
    );

void main() {
  group('ShellRipgrepRunner', () {
    test('用 POSIX 引号拼命令', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_shellResult());
      final ShellRipgrepRunner runner = ShellRipgrepRunner(shell);

      await runner.run(
        _rg,
        <String>['--', 'a b'],
        timeout: const Duration(seconds: 1),
        maxOutputBytes: 1024,
      );

      expect(shell.lastRequest?.command, "'rg' '--' 'a b'");
    });

    test('参数含单引号时转义', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_shellResult());
      final ShellRipgrepRunner runner = ShellRipgrepRunner(shell);

      await runner.run(
        _rg,
        <String>["it's"],
        timeout: const Duration(seconds: 1),
        maxOutputBytes: 1024,
      );

      expect(shell.lastRequest?.command, r"'rg' 'it'\''s'");
    });

    test('超时与输出上限透传给 shell 请求', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_shellResult());
      final ShellRipgrepRunner runner = ShellRipgrepRunner(shell);

      await runner.run(
        _rg,
        const <String>[],
        timeout: const Duration(seconds: 3),
        maxOutputBytes: 4096,
      );

      expect(shell.lastRequest?.timeoutMs, 3000);
      expect(shell.lastRequest?.stdoutMaxBytes, 4096);
    });

    test('ShellRunResult 映射为 RipgrepRunResult', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_shellResult(
          exitCode: 2, timedOut: true, stdout: 'out', stderr: 'err'));
      final ShellRipgrepRunner runner = ShellRipgrepRunner(shell);

      final RipgrepRunResult result = await runner.run(
        _rg,
        const <String>[],
        timeout: const Duration(seconds: 1),
        maxOutputBytes: 1024,
      );

      expect(result.exitCode, 2);
      expect(result.timedOut, isTrue);
      expect(result.stdout, 'out');
      expect(result.stderr, 'err');
    });
  });

  group('ProcessRipgrepRunner', () {
    const ProcessRipgrepRunner runner = ProcessRipgrepRunner();

    test('本地 rg 冒烟：输出版本', () async {
      final ProcessResult probe = Process.runSync('rg', <String>['--version']);
      if (probe.exitCode != 0) return;

      final RipgrepRunResult result = await runner.run(
        _rg,
        <String>['--version'],
        timeout: const Duration(seconds: 5),
        maxOutputBytes: 4096,
      );

      expect(result.timedOut, isFalse);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('ripgrep'));
    });

    test('超时 → 杀掉子进程并标记 timedOut', () async {
      if (Platform.isWindows) return;
      final Directory dir =
          Directory.systemTemp.createTempSync('conatus-rgto-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final String script = _script(dir, '#!/bin/sh\nexec sleep 30\n');

      final Stopwatch watch = Stopwatch()..start();
      final RipgrepRunResult result = await runner.run(
        RipgrepBinary(path: script, source: RipgrepSource.system),
        const <String>[],
        timeout: const Duration(milliseconds: 300),
        maxOutputBytes: 1024,
      );

      expect(result.timedOut, isTrue);
      expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
    });

    test('输出超过 maxOutputBytes 时截断', () async {
      if (Platform.isWindows) return;
      final Directory dir =
          Directory.systemTemp.createTempSync('conatus-rgcap-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final String script = _script(dir, "#!/bin/sh\nprintf 'abcdefghij'\n");

      final RipgrepRunResult result = await runner.run(
        RipgrepBinary(path: script, source: RipgrepSource.system),
        const <String>[],
        timeout: const Duration(seconds: 5),
        maxOutputBytes: 3,
      );

      expect(result.timedOut, isFalse);
      expect(result.exitCode, 0);
      expect(result.stdout, 'abc');
    });
  });
}

String _script(Directory dir, String body) {
  final File file = File('${dir.path}/fake_rg.sh')..writeAsStringSync(body);
  Process.runSync('chmod', <String>['+x', file.path]);
  return file.path;
}
