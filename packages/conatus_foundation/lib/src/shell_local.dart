/// shell 插件的本地实现：通过 `dart:io` 的 [Process] 执行命令。
///
/// 这是 [ShellExecutor] 的默认 provider，用 `bash -c`（Windows 用 `cmd /c`）
/// 运行命令，采集有上限的 stdout / stderr，并支持前台超时与后台进程句柄。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:conatus_core/conatus_core.dart';
import 'shell.dart';

/// 面向模型的终端环境：关闭颜色、分页器与交互特性，避免输出被转义码污染。
const Map<String, String> _envOverrides = <String, String>{
  'NO_COLOR': '1',
  'TERM': 'dumb',
  'PAGER': 'cat',
  'GIT_PAGER': 'cat',
};

/// exitCode 落定后，等待管道关闭的宽限期。
///
/// 进程被杀（cancel/超时）后，其孙进程可能以孤儿身份持有 stdout/stderr
/// 的管道写端，使流迟迟不关闭；宽限期过后返回已采集快照，调用方不再被
/// 挂到孙进程自然退出。
const Duration _pipeSettleGrace = Duration(milliseconds: 250);

/// 基于本地子进程的默认执行器。
class LocalShellExecutor implements ShellExecutor {
  LocalShellExecutor({
    this.cwd,
    this.timeoutMs = 120000,
    this.maxTimeoutMs = 600000,
    this.maxOutputBytes = 64000,
  });

  /// 相对工作目录的默认基准；缺省用 `Directory.current`。
  final String? cwd;

  /// 默认前台超时（毫秒）。
  final int timeoutMs;

  /// 单次超时覆盖的上限（毫秒）。
  final int maxTimeoutMs;

  /// 单路输出的内存采集上限（字节）。
  final int maxOutputBytes;

  @override
  ShellExecSpec resolve(ShellExecRequest request) {
    final int requested = request.timeoutMs ?? timeoutMs;
    return ShellExecSpec(
      command: request.command,
      workdir: request.workdir ?? cwd ?? Directory.current.path,
      timeoutMs: requested > maxTimeoutMs ? maxTimeoutMs : requested,
      stdoutMaxBytes: request.stdoutMaxBytes ?? maxOutputBytes,
      stdin: request.stdin,
      env: request.env,
      cancelSignal: request.cancelSignal,
    );
  }

  @override
  Future<ShellRunResult> run(ShellExecSpec spec) async {
    final Process process = await _spawn(spec);
    _writeStdin(process, spec.stdin);
    final Future<void>? cancel = spec.cancelSignal;
    if (cancel != null) {
      unawaited(cancel.then((_) => process.kill(ProcessSignal.sigkill)));
    }
    final _BoundedCollector stdout =
        _BoundedCollector(process.stdout, spec.stdoutMaxBytes)..start();
    final _BoundedCollector stderr =
        _BoundedCollector(process.stderr, maxOutputBytes)..start();
    bool timedOut = false;
    final Timer timer = Timer(Duration(milliseconds: spec.timeoutMs), () {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
    });
    final int exitCode = await process.exitCode;
    timer.cancel();
    await _awaitSettled(<Completer<void>>[stdout.finished, stderr.finished]);
    return ShellRunResult(
      exitCode: exitCode,
      timedOut: timedOut,
      timeoutMs: spec.timeoutMs,
      stdout: stdout.snapshot(),
      stderr: stderr.snapshot(),
    );
  }

  @override
  Future<ShellProcess> start(ShellExecSpec spec) async {
    final Process process = await _spawn(spec);
    _writeStdin(process, spec.stdin);
    return _LocalShellProcess(process, maxOutputBytes);
  }

  Future<Process> _spawn(ShellExecSpec spec) {
    final bool windows = Platform.isWindows;
    final String executable = windows ? 'cmd.exe' : 'bash';
    final List<String> args =
        windows ? <String>['/c', spec.command] : <String>['-c', spec.command];
    // IRREVERSIBLE: 命令一旦执行，其对外部世界的效果（写文件、发请求、删数据……）
    // 无法被任何撤销函数回滚。这里只返回进程句柄；不存在、也不假装存在能还原
    // 副作用的逆——调用前的审批/守卫是唯一的防线。
    return Process.start(
      executable,
      args,
      workingDirectory: spec.workdir,
      environment: <String, String>{..._envOverrides, ...?spec.env},
    );
  }

  void _writeStdin(Process process, String? input) {
    if (input == null) {
      unawaited(process.stdin.close());
      return;
    }
    process.stdin.write(input);
    unawaited(process.stdin.close());
  }
}

/// 后台进程句柄：缓冲输出，支持增量读取与终止。
class _LocalShellProcess implements ShellProcess {
  _LocalShellProcess(this._process, int maxBytes) {
    final Future<void> stdoutDone = _process.stdout
        .listen((List<int> chunk) =>
            _lossy = _append(_stdout, chunk, maxBytes) || _lossy)
        .asFuture();
    final Future<void> stderrDone = _process.stderr
        .listen((List<int> chunk) =>
            _lossy = _append(_stderr, chunk, maxBytes) || _lossy)
        .asFuture();
    _done = Future.wait<void>(<Future<void>>[
      _process.exitCode.then((int code) {
        _exitCode = code;
        if (_status == ShellProcessStatus.running) {
          _status = ShellProcessStatus.completed;
        }
      }),
      stdoutDone,
      stderrDone,
    ]).then((_) {});
  }

  final Process _process;
  final List<int> _stdout = <int>[];
  final List<int> _stderr = <int>[];
  late final Future<void> _done;
  ShellProcessStatus _status = ShellProcessStatus.running;
  int? _exitCode;
  int _outOffset = 0;
  int _errOffset = 0;
  bool _lossy = false;

  @override
  ShellProcessStatus get status => _status;

  @override
  int? get exitCode => _exitCode;

  @override
  Future<void> get done => _done;

  @override
  ShellProcessRead readOutput() {
    final String out =
        utf8.decode(_stdout.sublist(_outOffset), allowMalformed: true);
    _outOffset = _stdout.length;
    final String err =
        utf8.decode(_stderr.sublist(_errOffset), allowMalformed: true);
    _errOffset = _stderr.length;
    final String delta = _joinOutput(out, err);
    return ShellProcessRead(delta: delta, lossy: _lossy);
  }

  @override
  bool kill() {
    if (_status != ShellProcessStatus.running) return false;
    _status = ShellProcessStatus.killed;
    _process.kill(ProcessSignal.sigkill);
    return true;
  }

  static String _joinOutput(String out, String err) {
    if (err.isEmpty) return out;
    final String section = '[stderr]\n$err';
    return out.isEmpty ? section : '$out\n$section';
  }
}

/// 有界采集：把 [stream] 持续收进 [buffer]；[finished] 在流关闭（或出错）时落定。
///
/// 与「await 采集 future」的区别：buffer 随时可快照——进程被杀后若孙进程
/// 孤儿持有管道 fd，流迟迟不关闭，调用方可以宽限期后取走已采集部分，
/// 而不是挂到孤儿自然退出。
class _BoundedCollector {
  _BoundedCollector(this._stream, this._maxBytes);

  final Stream<List<int>> _stream;
  final int _maxBytes;
  final List<int> buffer = <int>[];
  final Completer<void> finished = Completer<void>();
  bool truncated = false;

  void start() {
    _stream.listen(
      (List<int> chunk) =>
          truncated = _append(buffer, chunk, _maxBytes) || truncated,
      onError: (Object _) => finished.complete(),
      onDone: finished.complete,
    );
  }

  /// 当前已采集内容的快照（不结束采集）。
  CollectedOutput snapshot() => CollectedOutput(
        text: utf8.decode(buffer, allowMalformed: true),
        truncated: truncated,
      );
}

/// 等全部 [completers] 落定，最长 [_pipeSettleGrace]；逾期按已落定处理。
Future<void> _awaitSettled(List<Completer<void>> completers) async {
  await Future.any<void>(<Future<void>>[
    Future.wait<void>(completers.map((Completer<void> c) => c.future)),
    Future<void>.delayed(_pipeSettleGrace),
  ]);
}

/// 把 [chunk] 追加到 [bytes]，超过 [maxBytes] 时截断并返回 true。
bool _append(List<int> bytes, List<int> chunk, int maxBytes) {
  if (bytes.length >= maxBytes) return true;
  final int remaining = maxBytes - bytes.length;
  if (chunk.length <= remaining) {
    bytes.addAll(chunk);
    return false;
  }
  bytes.addAll(chunk.sublist(0, remaining));
  return true;
}

/// 提供本地执行器为 `'shell'` 服务；[executor] 用于注入自定义实现。
ShellExecutor provideShellLocal(Context ctx, {ShellExecutor? executor}) {
  final ShellExecutor resolved = executor ?? LocalShellExecutor();
  ctx.provide('shell', resolved);
  return resolved;
}
