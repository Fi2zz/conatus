/// 流程调度器：接口、事件与装配入口。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_cron/conatus_cron.dart';

import 'automation.dart';
import 'engine.dart';
import 'run.dart';
import 'scheduler_impl.dart';

/// 流程调度器。让 workflow 从「被调用的」变成「自动运行的」：
/// 触发器 + 约束 + 后处理。
abstract class WorkflowScheduler {
  /// 注册自动化。
  void register(Automation automation);

  /// 注销自动化。
  void unregister(String name);

  /// 开始调度。自动触发（定时 / 事件 / 条件）开始生效。
  void start();

  /// 停止调度。自动触发暂停；手动触发不受影响。
  void stop();

  /// 手动触发一次。不受 start/stop 影响。
  Future<WorkflowRun?> trigger(String name);

  /// cron 运行时交付入口：把到期任务映射回自动化并触发。
  ///
  /// 装配者把它接到 [CronRuntime] 的 deliver 端口。
  Future<bool> handleCronDelivery(
      String recordId, String framing, CronTask task);

  /// 已注册的自动化。
  List<Automation> get automations;

  /// 变更流。
  Stream<SchedulerEvent> get changes;

  /// 释放资源。
  void dispose();
}

/// 调度事件。
sealed class SchedulerEvent {
  const SchedulerEvent();
}

/// 自动化注册成功。
class AutomationRegistered extends SchedulerEvent {
  const AutomationRegistered(this.automation);

  final Automation automation;
}

/// 自动化已触发（run 可能为 null）。
class AutomationTriggered extends SchedulerEvent {
  const AutomationTriggered(this.name, this.run);

  final String name;
  final WorkflowRun? run;
}

/// 自动化被约束或冷却阻塞。
class AutomationBlocked extends SchedulerEvent {
  const AutomationBlocked(this.name, this.reason);

  final String name;
  final String reason;
}

/// 把 [WorkflowScheduler] 作为 `'workflowScheduler'` 服务提供到上下文。
///
/// [workflow] 必填；[cron] / [telemetry] 可选，缺省对应触发器不自动触发。
/// 定时触发装配示例：
///
/// ```dart
/// final scheduler = provideWorkflowScheduler(ctx,
///     workflow: provideWorkflow(ctx),
///     cron: provideCron(ctx, storage: storage));
/// provideCronRuntime(ctx,
///     deliver: (id, framing, task) =>
///         scheduler.handleCronDelivery(id, framing, task));
/// ```
WorkflowScheduler provideWorkflowScheduler(
  Context ctx, {
  required WorkflowEngine workflow,
  CronService? cron,
  Telemetry? telemetry,
  Set<String> Function()? permissionsOf,
  DateTime Function()? now,
}) {
  final scheduler = WorkflowSchedulerImpl(
    workflow: workflow,
    cron: cron,
    telemetry: telemetry,
    permissionsOf: permissionsOf,
    now: now,
  );
  ctx.onDispose(scheduler.dispose);
  ctx.provide('workflowScheduler', scheduler);
  return scheduler;
}

/// `ctx.scheduler`：当前上下文可见的 [WorkflowScheduler]。
extension SchedulerContext on Context {
  /// 当前上下文提供的流程调度器。
  WorkflowScheduler get scheduler =>
      require<WorkflowScheduler>('workflowScheduler');
}
