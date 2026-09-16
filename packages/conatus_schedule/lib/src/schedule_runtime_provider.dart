/// 到期运行时的装配入口。
library;

import 'dart:async';

import 'package:conatus_core/conatus_core.dart';

import 'schedule.dart';
import 'schedule_runtime.dart';

/// 把 [ScheduleRuntime] 作为 `'scheduleRuntime'` 服务提供到上下文并立即推导一次。
///
/// [deliver] 由装配方提供（例如界面层：空闲时投递并返回 `true`，忙时返回
/// `false`）；运行时随上下文释放而停止，不删除任何持久记录。
ScheduleRuntime provideScheduleRuntime(
  Context ctx, {
  required ScheduleDelivery deliver,
  SessionSchedule? schedule,
  DateTime Function()? clock,
  void Function(String message)? onWarning,
}) {
  final ScheduleRuntime runtime = ScheduleRuntime(
    schedule: schedule ?? ctx.schedule,
    deliver: deliver,
    clock: clock,
    onWarning: onWarning,
  );
  ctx.provide('scheduleRuntime', runtime);
  ctx.onDispose(() => unawaited(runtime.dispose()));
  runtime.requestDrive();
  return runtime;
}

/// `ctx.scheduleRuntime`：当前上下文可见的到期运行时。
extension ScheduleRuntimeContext on Context {
  /// 当前上下文提供的到期运行时。
  ScheduleRuntime get scheduleRuntime =>
      require<ScheduleRuntime>('scheduleRuntime');
}
