/// cron 运行时的装配入口。
library;

import 'package:conatus_core/conatus_core.dart';

import 'cron.dart';
import 'cron_runtime.dart';

/// 把 [CronRuntime] 作为 `'cronRuntime'` 服务提供到上下文并启动定时器。
///
/// [deliver] 由装配方注入（把 framing 投递进目标会话；返回 false 表示暂时
/// 无法投递，下个 tick 重试）；运行时随上下文释放自动停表，不删除任何持久记录。
CronRuntime provideCronRuntime(
  Context ctx, {
  CronService? service,
  required CronDelivery deliver,
  CronRuntimeOptions options = const CronRuntimeOptions(),
}) {
  final CronRuntime runtime = CronRuntime(
    service: service ?? ctx.cron,
    deliver: deliver,
    options: options,
  );
  ctx.provide('cronRuntime', runtime);
  ctx.onDispose(runtime.dispose);
  return runtime;
}

/// `ctx.cronRuntime`：当前上下文可见的 cron 运行时。
extension CronRuntimeContext on Context {
  /// 当前上下文提供的 cron 运行时。
  CronRuntime get cronRuntime => require<CronRuntime>('cronRuntime');
}
