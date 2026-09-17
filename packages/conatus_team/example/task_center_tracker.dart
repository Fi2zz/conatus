/// 接线示例：把 [TaskCenter] 适配成 conatus_team 的 [TeamTaskTracker]。
///
/// conatus_team 刻意不依赖 conatus_tasks（实验性包不扩大依赖面），
/// 团队成员与任务中心的接通由装配方在主程序侧完成。本文件就是那个
/// adapter：spawn 成员 → 建一个 `subAgent` 任务并置 running；
/// remove 成员 → 按结局置 completed / failed。
///
/// 用法：
/// ```dart
/// final TaskCenter tasks = provideTaskCenter(ctx);
/// provideAgentTeam(
///   ctx,
///   taskTracker: TaskCenterTeamTracker(tasks),
/// );
/// ```
///
/// 映射 teammateId → Task.id 在 adapter 内部维护；终态重复落定
/// （`already-terminal`）与未知成员（`not-found`）静默忽略，与
/// `TrackingShellExecutor` 的容错风格一致。
library;

import 'dart:async';

import 'package:conatus_tasks/conatus_tasks.dart';
import 'package:conatus_team/conatus_team.dart';

/// 把团队成员生命周期映射到 [TaskCenter] 的 [TeamTaskTracker] 实现。
class TaskCenterTeamTracker implements TeamTaskTracker {
  TaskCenterTeamTracker(this._tasks);

  final TaskCenter _tasks;

  /// teammateId → Task.id 映射。
  final Map<String, String> _taskByTeammate = <String, String>{};

  @override
  Future<String?> beginMember({
    required String teammateId,
    required String name,
    required String leadId,
  }) async {
    final Task task = await _tasks.create(
      kind: TaskKind.subAgent,
      description: '团队成员: $name',
      metadata: <String, Object?>{
        'teammateId': teammateId,
        'leadId': leadId,
      },
    );
    _taskByTeammate[teammateId] = task.id;
    await _safeUpdate(task.id, status: TaskStatus.running);
    return task.id;
  }

  @override
  Future<void> completeMember(String teammateId, {Object? result}) =>
      _settle(teammateId, TaskStatus.completed, result: result);

  @override
  Future<void> failMember(String teammateId, {Object? error}) =>
      _settle(teammateId, TaskStatus.failed, error: error);

  Future<void> _settle(
    String teammateId,
    TaskStatus status, {
    Object? result,
    Object? error,
  }) async {
    final String? taskId = _taskByTeammate[teammateId];
    if (taskId == null) return;
    await _safeUpdate(taskId,
        status: status, result: result, error: error);
    _taskByTeammate.remove(teammateId);
  }

  /// 容忍任务已终态 / 已不存在（级联清理顺序可能先落定）。
  Future<void> _safeUpdate(
    String taskId, {
    required TaskStatus status,
    Object? result,
    Object? error,
  }) async {
    try {
      await _tasks.update(taskId,
          status: status, result: result, error: error);
    } on TaskException catch (e) {
      if (e.code != 'already-terminal' && e.code != 'not-found') rethrow;
    }
  }
}
