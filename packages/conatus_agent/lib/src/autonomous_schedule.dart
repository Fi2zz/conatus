/// 自主运营的定时启动：把到期提醒接到 [AutonomousRunner]。
///
/// 复用 `conatus_schedule` 的到期运行时：`schedule/change` 事件仍是唯一权威，
/// [ScheduleRuntime] 到期后经 deliver 端口触发——本集成把 deliver 实现为
/// 「到点后台启动一轮自主运营」。已在跑时返回 `false`（不写 dispatch，记录
/// 保持活动、下次重试）。装配入口 [provideAutonomousSchedule] 不占用
/// `'scheduleRuntime'` 服务键，可与宿主自己的到期投递（如界面空闲投递）并存。
library;

import 'dart:async';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_schedule/conatus_schedule.dart';
import 'autonomous_runner.dart';

/// 把到期提醒接到自主运营的 deliver 端口：空闲时后台触发一轮
/// [AutonomousRunner.run]，返回 `true`；已在运行返回 `false`。
///
/// 单轮失败经 [onError] 上报（缺省静默——失败已记入审计/遥测，若装配），
/// 不会中断后续调度。
ScheduleDelivery autonomousDelivery(
  AutonomousRunner runner, {
  void Function(Object error)? onError,
}) {
  return (String text) async {
    if (runner.isRunning) return false;
    unawaited(_runInBackground(runner, onError));
    return true;
  };
}

/// 把自主运营定时启动装配进上下文：提供 `'autonomousSchedule'` 服务。
///
/// 依赖 `'schedule'` 服务（[provideSessionSchedule]），未显式传入 [schedule]
/// 时从上下文解析。自驱动：任何 `schedule/change` 事件落盘都会触发重新推导
/// （新建提醒无需宿主介入即可定时触发），装配时立即推导一次。
ScheduleRuntime provideAutonomousSchedule(
  Context ctx, {
  required AutonomousRunner runner,
  SessionSchedule? schedule,
  DateTime Function()? clock,
  void Function(Object error)? onError,
}) {
  final SessionSchedule resolved =
      schedule ?? ctx.require<SessionSchedule>('schedule');
  final ScheduleRuntime runtime = ScheduleRuntime(
    schedule: resolved,
    deliver: autonomousDelivery(runner, onError: onError),
    clock: clock,
  );
  ctx.provide('autonomousSchedule', runtime);
  ctx.onDispose(() => unawaited(runtime.dispose()));
  final Disposer off = resolved.session.onEvent((SessionEvent event) {
    if (event.type == kScheduleChangeEvent) runtime.requestDrive();
  });
  ctx.onDispose(off);
  runtime.requestDrive();
  return runtime;
}

/// `ctx.autonomousSchedule`：当前上下文可见的自主运营定时运行时。
extension AutonomousScheduleContext on Context {
  /// 当前上下文提供的自主运营定时运行时。
  ScheduleRuntime get autonomousSchedule =>
      require<ScheduleRuntime>('autonomousSchedule');
}

/// 后台跑一轮；失败只上报，不向调度传播。
Future<void> _runInBackground(
  AutonomousRunner runner,
  void Function(Object error)? onError,
) async {
  try {
    await runner.run();
  } on Object catch (error) {
    final void Function(Object error)? handler = onError;
    if (handler != null) handler(error);
  }
}
