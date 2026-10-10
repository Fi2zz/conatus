/// 后台进程 kill 的进程树语义（E-15）：kill 根进程时孙进程不再孤儿化。
library;

import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

/// 唯一签名，避免撞上其他测试的 sleep 进程。
const String _sig1 = '8642';
const String _sig2 = '8643';
const String _pattern = 'sleep $_sig1|sleep $_sig2';

bool _descendantsAlive() {
  final ProcessResult result =
      Process.runSync('pgrep', <String>['-f', _pattern]);
  return result.exitCode == 0 && '${result.stdout}'.trim().isNotEmpty;
}

Future<void> _waitUntilGone() async {
  for (int i = 0; i < 40; i++) {
    if (!_descendantsAlive()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  test('LocalShellExecutor 后台进程 kill 连带终结孙进程', () async {
    if (Platform.isWindows) return;
    final LocalShellExecutor exec = LocalShellExecutor();
    final ShellExecSpec spec = exec.resolve(
      const ShellExecRequest(command: 'sleep $_sig1 & sleep $_sig2'),
    );
    final ShellProcess process = await exec.start(spec);
    addTearDown(() {
      final ProcessResult r =
          Process.runSync('pgrep', <String>['-f', _pattern]);
      for (final String line in '${r.stdout}'.split('\n')) {
        final int? v = int.tryParse(line.trim());
        if (v != null) Process.killPid(v, ProcessSignal.sigkill);
      }
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(_descendantsAlive(), isTrue, reason: '孙进程应已起来');

    expect(process.kill(), isTrue);
    await _waitUntilGone();

    expect(_descendantsAlive(), isFalse, reason: '孙进程应随根一并被终结');
  }, testOn: '!windows');

  test('killProcessTree 幂等：目标已消失不抛', () async {
    // 一个已退出进程的 pid（直接结束的 sleep）。
    final Process p = await Process.start('bash', <String>['-c', 'exit 0']);
    final int pid = p.pid;
    await p.exitCode;
    await expectLater(killProcessTree(pid), completes);
  }, testOn: '!windows');
}
