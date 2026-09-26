import 'dart:async';
import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  group('LocalShellExecutor.resolve', () {
    test('补齐 workdir，并对 timeout 封顶', () {
      final executor = LocalShellExecutor(
        cwd: '/tmp',
        timeoutMs: 1000,
        maxTimeoutMs: 5000,
      );

      final ShellExecSpec spec = executor
          .resolve(const ShellExecRequest(command: 'ls', timeoutMs: 9000));

      expect(spec.workdir, '/tmp');
      expect(spec.timeoutMs, 5000);
      expect(spec.stdoutMaxBytes, 64000);
    });

    test('缺省 timeout 用实现默认值', () {
      final executor = LocalShellExecutor(timeoutMs: 1234);
      final ShellExecSpec spec =
          executor.resolve(const ShellExecRequest(command: 'ls'));
      expect(spec.timeoutMs, 1234);
    });
  });

  group('LocalShellExecutor.run', () {
    test('采集 stdout 与退出码', () async {
      final executor = LocalShellExecutor();
      final ShellRunResult result = await executor.run(
        executor.resolve(const ShellExecRequest(command: 'echo hello')),
      );

      expect(result.exitCode, 0);
      expect(result.timedOut, isFalse);
      expect(result.stdout.text.trim(), 'hello');
    });

    test('stderr 独立采集', () async {
      final executor = LocalShellExecutor();
      final ShellRunResult result = await executor.run(
        executor.resolve(
          const ShellExecRequest(command: 'echo boom 1>&2'),
        ),
      );

      expect(result.stderr.text.trim(), 'boom');
    });

    test('stdin 透传', () async {
      final executor = LocalShellExecutor();
      final ShellRunResult result = await executor.run(
        executor
            .resolve(const ShellExecRequest(command: 'cat', stdin: 'piped')),
      );

      expect(result.stdout.text, 'piped');
    });

    test('非零退出正常返回而非抛异常', () async {
      final executor = LocalShellExecutor();
      final ShellRunResult result = await executor.run(
        executor.resolve(const ShellExecRequest(command: 'exit 3')),
      );

      expect(result.exitCode, 3);
      expect(result.timedOut, isFalse);
    });

    test('超时中断：timedOut 为 true', () async {
      final executor = LocalShellExecutor(timeoutMs: 300);
      final ShellRunResult result = await executor.run(
        executor.resolve(const ShellExecRequest(command: 'sleep 5')),
      );

      expect(result.timedOut, isTrue);
    });

    test('输出超上限被截断', () async {
      final executor = LocalShellExecutor(maxOutputBytes: 4);
      final ShellRunResult result = await executor.run(
        executor.resolve(const ShellExecRequest(command: 'printf abcdefgh')),
      );

      expect(result.stdout.truncated, isTrue);
      expect(result.stdout.text, 'abcd');
    });

    test('cancelSignal 落定 → 进程被终止', () async {
      final executor = LocalShellExecutor();
      final Completer<void> cancel = Completer<void>();
      final Future<ShellRunResult> pending = executor.run(executor.resolve(
        ShellExecRequest(command: 'sleep 30', cancelSignal: cancel.future),
      ));
      cancel.complete();

      final ShellRunResult result = await pending;

      expect(result.exitCode, isNot(0));
      expect(result.timedOut, isFalse);
    });

    test('run cancel 后孙进程孤儿持有管道也不挂起', () async {
      if (Platform.isWindows) return;
      // 脚本内 sleep：bash 不 exec 优化，cancel 杀 bash 后 sleep 成孤儿持管道。
      final Directory tmp = Directory.systemTemp.createTempSync('shell-orphan-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final File script = File('${tmp.path}/s.sh')
        ..writeAsStringSync('sleep 30\n');
      final executor = LocalShellExecutor();
      final Completer<void> cancel = Completer<void>();
      final Stopwatch sw = Stopwatch()..start();
      final Future<ShellRunResult> pending = executor.run(executor.resolve(
        ShellExecRequest(command: 'bash ${script.path}', cancelSignal: cancel.future),
      ));
      Timer(const Duration(milliseconds: 300), cancel.complete);
      final ShellRunResult result = await pending;
      sw.stop();
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      expect(result.exitCode, isNot(0)); // 被 SIGKILL
    });

    test('正常命令不受宽限期拖累', () async {
      if (Platform.isWindows) return;
      final executor = LocalShellExecutor();
      final Stopwatch sw = Stopwatch()..start();
      final ShellRunResult result = await executor.run(
        executor.resolve(const ShellExecRequest(command: "bash -c 'echo hi'")),
      );
      sw.stop();
      expect(result.stdout.text, contains('hi'));
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });

  group('LocalShellExecutor.start', () {
    test('后台进程：done 落定后增量读取，kill 幂等', () async {
      final executor = LocalShellExecutor();
      final ShellProcess process = await executor.start(
        executor.resolve(const ShellExecRequest(command: 'echo bg')),
      );

      expect(process.status, ShellProcessStatus.running);
      await process.done;

      expect(process.status, ShellProcessStatus.completed);
      expect(process.exitCode, 0);
      expect(process.readOutput().delta.trim(), 'bg');
      // 连续读取不重复投递。
      expect(process.readOutput().delta, isEmpty);
      expect(process.kill(), isFalse);
    });

    test('kill 运行中的进程', () async {
      final executor = LocalShellExecutor();
      final ShellProcess process = await executor.start(
        executor.resolve(const ShellExecRequest(command: 'sleep 5')),
      );

      expect(process.kill(), isTrue);
      await process.done;
      expect(process.status, ShellProcessStatus.killed);
    });
  });

  group('provideShellLocal', () {
    test('作为 shell 服务提供，可注入自定义实现', () {
      final ctx = Context.root();
      final LocalShellExecutor custom = LocalShellExecutor(cwd: '/tmp');
      final ShellExecutor executor = provideShellLocal(ctx, executor: custom);

      expect(identical(executor, custom), isTrue);
      expect(identical(ctx.require<ShellExecutor>('shell'), custom), isTrue);
      ctx.dispose();
    });
  });
}
