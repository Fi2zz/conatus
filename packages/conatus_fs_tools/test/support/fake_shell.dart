import 'package:conatus_foundation/conatus_foundation.dart';

/// 预置返回结果的 ShellExecutor 测试替身，记录最后一次请求。
class FakeShellExecutor implements ShellExecutor {
  FakeShellExecutor([this.result]);

  ShellRunResult? result;

  /// 最后一次传入 [resolve] 的请求。
  ShellExecRequest? lastRequest;

  @override
  ShellExecSpec resolve(ShellExecRequest request) {
    lastRequest = request;
    return ShellExecSpec(
      command: request.command,
      workdir: request.workdir ?? '',
      timeoutMs: request.timeoutMs ?? 0,
      stdoutMaxBytes: request.stdoutMaxBytes ?? 0,
      stdin: request.stdin,
      env: request.env,
    );
  }

  @override
  Future<ShellRunResult> run(ShellExecSpec spec) async => result!;

  @override
  Future<ShellProcess> start(ShellExecSpec spec) =>
      throw UnimplementedError('FakeShellExecutor.start');
}
