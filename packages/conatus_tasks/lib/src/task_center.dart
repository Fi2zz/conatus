/// task 插件的服务端口。
///
/// [TaskCenter] 只追踪任务状态，不调度也不执行任务。任务由 Agent Loop /
/// sub-agent / shell / schedule 等运行时组件经 [TaskTracking] 装饰器创建，
/// 模型侧只有 `list_tasks` / `cancel_task` 两个只读/治理工具。状态机：
/// pending → running ⇄ paused，任一非终态可转 completed / failed /
/// cancelled（终态不可再变更）。
library;

import 'dart:async';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'task.dart';

/// 任务中心服务。
abstract class TaskCenter {
  /// 创建任务。返回的 Task 处于 pending 状态。
  Future<Task> create({
    required TaskKind kind,
    required String description,
    String? parentTaskId,
    Map<String, Object?>? metadata,
  });

  /// 更新任务状态。
  ///
  /// - status 进入 running 时自动设置 startedAt；
  /// - status 进入终态时自动设置 finishedAt；
  /// - 终态任务不可再更新，抛 [TaskException]（`already-terminal`）；
  /// - 任务不存在抛 [TaskException]（`not-found`）。
  Future<Task> update(
    String id, {
    TaskStatus? status,
    Object? result,
    Object? error,
  });

  /// 查询单个任务。
  Task? get(String id);

  /// 所有任务。
  List<Task> get all;

  /// 活跃任务（pending + running + paused）。
  List<Task> get active;

  /// 指定任务的直接子任务。
  List<Task> childrenOf(String parentId);

  /// 指定任务的整棵子树（含自己）。
  List<Task> subtreeOf(String id);

  /// 取消任务：级联取消活跃子任务，执行 [registerCancel] 注册的取消回调；
  /// shell 类任务走 approval 确认（若提供）。拒绝时抛 [TaskException]。
  Future<void> cancel(String id);

  /// 取消指定任务的所有活跃子任务。不取消自己。
  Future<void> cancelChildren(String id);

  /// 注册取消回调：[cancel] 落状态前调用（如 kill 进程）。允许覆盖。
  void registerCancel(String id, Future<void> Function() canceller);

  /// 任务变更流（每次状态落盘后广播最新整值）。
  Stream<Task> get changes;

  /// 从 Session 恢复状态；未完成的活跃任务标记为 failed（执行环境已丢失）。
  void restore(Session session);

  /// 释放资源。幂等。
  void dispose();
}

/// `ctx.tasks`：当前上下文可见的任务中心。
extension TasksContext on Context {
  /// 取当前上下文可见的 [TaskCenter]（未提供时抛 [StateError]）。
  TaskCenter get tasks => require<TaskCenter>('tasks');
}
