/// shell 插件（能力缝 / Service Definition）：抽象的命令执行契约。
///
/// 服务键 `'shell'`，只定义接口，具体实现由 provider 提供（内置实现见
/// `shell_local.dart` 的 [LocalShellExecutor] / `provideShellLocal`）。
/// 这样沙箱执行器、远程执行器或 PowerShell 执行器都能替换默认实现，
/// 而消费方只依赖本契约。
library;

import 'package:conatus_core/conatus_core.dart';

/// 一路被采集的输出（可能因超过上限被截断）。
class CollectedOutput {
  const CollectedOutput({
    required this.text,
    this.truncated = false,
    this.spillPath,
  });

  /// 保留的文本（截断时为尾部）。
  final String text;

  /// 是否发生截断。
  final bool truncated;

  /// 完整输出的落盘路径（若执行器提供了 spill）。
  final String? spillPath;
}

/// 前台命令的**请求**：可缺省字段由 [ShellExecutor.resolve] 依据实现配置补齐。
class ShellExecRequest {
  const ShellExecRequest({
    required this.command,
    this.workdir,
    this.timeoutMs,
    this.stdoutMaxBytes,
    this.stdin,
    this.env,
    this.cancelSignal,
  });

  /// 要执行的命令。
  final String command;

  /// 工作目录覆盖；缺省用实现配置。
  final String? workdir;

  /// 超时覆盖（毫秒）；实现会封顶。
  final int? timeoutMs;

  /// 前台 stdout 采集预算（字节）；缺省用实现的默认上限。
  final int? stdoutMaxBytes;

  /// 写入 stdin 后立即关闭；缺省表示不写。
  final String? stdin;

  /// 追加环境变量。
  final Map<String, String>? env;

  /// 取消信号：落定时终止进程（若实现支持）。缺省不取消。
  final Future<void>? cancelSignal;
}

/// 解析后的**执行规格**：必填字段已由 [ShellExecutor.resolve] 补齐并封顶。
class ShellExecSpec {
  const ShellExecSpec({
    required this.command,
    required this.workdir,
    required this.timeoutMs,
    required this.stdoutMaxBytes,
    this.stdin,
    this.env,
    this.cancelSignal,
  });

  /// 要执行的命令。
  final String command;

  /// 已解析的工作目录。
  final String workdir;

  /// 已封顶的超时（毫秒）。
  final int timeoutMs;

  /// 已解析的 stdout 采集上限（字节）。
  final int stdoutMaxBytes;

  /// 写入 stdin 后立即关闭；缺省表示不写。
  final String? stdin;

  /// 追加环境变量。
  final Map<String, String>? env;

  /// 取消信号（透传自请求）：落定时终止进程。
  final Future<void>? cancelSignal;
}

/// 一次前台运行的结局。
///
/// 正交的结局各自独立上报：进程可能既超时又以 0 退出（命令自己处理了信号），
/// 因此 [timedOut] 与 [exitCode] 互不覆盖。
class ShellRunResult {
  const ShellRunResult({
    required this.exitCode,
    required this.timedOut,
    required this.timeoutMs,
    required this.stdout,
    required this.stderr,
  });

  /// 退出码；被信号杀死时为 null。
  final int? exitCode;

  /// 是否由执行器自身的超时先行中断。
  final bool timedOut;

  /// 本次实际生效的超时（毫秒）。
  final int timeoutMs;

  /// stdout 采集结果。
  final CollectedOutput stdout;

  /// stderr 采集结果。
  final CollectedOutput stderr;
}

/// 后台进程的生命周期状态。
enum ShellProcessStatus { running, completed, killed }

/// 一次增量的 [ShellProcess.readOutput] 读取：自上次读取以来产生的内容。
class ShellProcessRead {
  const ShellProcessRead({
    required this.delta,
    this.lossy = false,
    this.stdoutSpillPath,
    this.stderrSpillPath,
  });

  /// 自上次读取以来的增量输出（stderr 以标记段拼接）。
  final String delta;

  /// 是否因截断丢失了增量无法包含的字节。
  final bool lossy;

  /// stdout 完整输出的落盘路径（若发生截断且可提供）。
  final String? stdoutSpillPath;

  /// stderr 完整输出的落盘路径（若发生截断且可提供）。
  final String? stderrSpillPath;
}

/// 后台进程句柄：唯一的访问入口，退出后缓冲输出仍可读。
abstract class ShellProcess {
  /// 进程生命周期状态（恰好落定一次）。
  ShellProcessStatus get status;

  /// 结束后的退出码（null = 被信号杀死 / 仍在运行）。
  int? get exitCode;

  /// 底层进程落定时完成；永不 reject。
  Future<void> get done;

  /// 读取自上次调用以来产生的新输出（消费式，不重复投递）。
  ShellProcessRead readOutput();

  /// 终止进程；进程已结束时返回 false（幂等）。
  bool kill();
}

/// 命令执行能力缝。
///
/// 实现必须遵守：
/// * [run] 只对基础设施故障 reject；非零退出、超时中断、取消中断都以
///   [ShellRunResult] 正常返回。
/// * [start] 立即返回句柄；后台进程无超时，[ShellProcess.done] 在进程结束时
///   落定且永不 reject。
/// * [ShellProcess.readOutput] 是增量的：连续读取不重复输出。
abstract class ShellExecutor {
  /// 依据实现配置补齐并封顶 [request]，产出可交给 [run]/[start] 的规格。
  ShellExecSpec resolve(ShellExecRequest request);

  /// 前台执行，进程结束时返回。
  Future<ShellRunResult> run(ShellExecSpec spec);

  /// 启动后台进程并立即返回句柄。
  Future<ShellProcess> start(ShellExecSpec spec);
}

/// 将自定义 [executor] 作为 `'shell'` 服务提供到上下文。
void provideShell(Context ctx, {required ShellExecutor executor}) {
  ctx.provide('shell', executor);
}
