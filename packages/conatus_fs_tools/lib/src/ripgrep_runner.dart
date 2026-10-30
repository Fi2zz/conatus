import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';

import 'ripgrep_binary.dart';

/// 一次 ripgrep 运行的结局。
class RipgrepRunResult {
  const RipgrepRunResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.timedOut = false,
  });

  /// 退出码；子进程被杀死且拿不到退出码时为 `-1`。
  final int exitCode;

  /// 标准输出（可能已按上限截断）。
  final String stdout;

  /// 标准错误（可能已按上限截断）。
  final String stderr;

  /// 是否因超时被中断。
  final bool timedOut;
}

/// ripgrep 执行接缝：决定命令如何落到目标环境。
///
/// 实现方负责把参数原样交给 rg（不做额外引号处理），并按 [maxOutputBytes]
/// 与 [timeout] 约束采集。
abstract class RipgrepRunner {
  /// 用 [binary] 执行一次 rg，参数为 [args]（已含 `--` 分隔符）。
  Future<RipgrepRunResult> run(
    RipgrepBinary binary,
    List<String> args, {
    required Duration timeout,
    required int maxOutputBytes,
  });
}

/// 经 `shell` 接缝执行：把命令拼成 POSIX 单引号字符串。
///
/// 适用于 nava 的本地 shell 与远程 shell；Windows 桌面端请用
/// [ProcessRipgrepRunner]（不经过 shell 引号解析）。
class ShellRipgrepRunner implements RipgrepRunner {
  const ShellRipgrepRunner(this.shell);

  /// 命令执行接缝。
  final ShellExecutor shell;

  @override
  Future<RipgrepRunResult> run(
    RipgrepBinary binary,
    List<String> args, {
    required Duration timeout,
    required int maxOutputBytes,
  }) async {
    final String command = <String>[binary.path, ...args].map(_quote).join(' ');
    final ShellExecSpec spec = shell.resolve(ShellExecRequest(
      command: command,
      timeoutMs: timeout.inMilliseconds,
      stdoutMaxBytes: maxOutputBytes,
    ));
    final ShellRunResult result = await shell.run(spec);
    return RipgrepRunResult(
      exitCode: result.exitCode ?? -1,
      stdout: result.stdout.text,
      stderr: result.stderr.text,
      timedOut: result.timedOut,
    );
  }

  /// POSIX 单引号：内部单引号写成 `'\''`。
  String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
}

/// 直接 `Process.start` 本地二进制：不经 shell，因此无需命令引号。
///
/// **绕过 `'shell'` 接缝，只适用于本地进程**；远程沙箱 / 非本机执行环境
/// 必须注入自己的 [RipgrepRunner]，否则 rg 会在宿主进程里执行。
class ProcessRipgrepRunner implements RipgrepRunner {
  const ProcessRipgrepRunner();

  /// 子进程退出后等待管道排空的宽限时间。
  static const Duration _drainGrace = Duration(seconds: 2);

  @override
  Future<RipgrepRunResult> run(
    RipgrepBinary binary,
    List<String> args, {
    required Duration timeout,
    required int maxOutputBytes,
  }) async {
    final Process process = await Process.start(binary.path, args);
    final List<int> out = <int>[];
    final List<int> err = <int>[];
    final Future<void> outDone = _drain(process.stdout, out, maxOutputBytes);
    final Future<void> errDone = _drain(process.stderr, err, maxOutputBytes);
    final bool timedOut = await _waitOrKill(process, timeout);
    final int code = await process.exitCode;
    await _settle(outDone, errDone);
    return RipgrepRunResult(
      exitCode: code,
      stdout: _decode(out),
      stderr: _decode(err),
      timedOut: timedOut,
    );
  }

  /// 等待管道排空；子进程的后代仍持有管道时最多再等 [_drainGrace]，
  /// 避免 runner 永久挂起（宁可丢尾部输出也不卡死调用方）。
  Future<void> _settle(Future<void> first, Future<void> second) async {
    await Future.wait(<Future<void>>[first, second])
        .timeout(_drainGrace, onTimeout: () => const <void>[]);
  }

  /// 等待退出；超时则杀掉子进程并返回 `true`。
  Future<bool> _waitOrKill(Process process, Duration timeout) async {
    try {
      await process.exitCode.timeout(timeout);
      return false;
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      return true;
    }
  }

  /// 持续排空管道（避免子进程被管道背压卡死），只保留前 [maxBytes] 字节。
  Future<void> _drain(Stream<List<int>> stream, List<int> sink, int maxBytes) =>
      stream.forEach((List<int> chunk) {
        final int room = maxBytes - sink.length;
        if (room <= 0) return;
        sink.addAll(chunk.length <= room ? chunk : chunk.sublist(0, room));
      });

  String _decode(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);
}
