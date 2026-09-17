/// 团队运行时 hook：聚合 4 个可选 seam（任务追踪 / 会话日志 / 审批 / 遥测）。
///
/// [AgentTeamImpl] 在每个操作的开头 / 结尾调用本类的 onXxx，所有 seam
/// 都是可选的——未注入时对应行为是 no-op。seam 异常被捕获并降级，
/// 不污染主流程。
library;

import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'team_task_tracker.dart';

/// 团队运行时 hook 聚合：4 个可选 seam 的横切调用点。
class TeamHooks {
  TeamHooks({this.taskTracker, this.session, this.approval, this.telemetry});

  final TeamTaskTracker? taskTracker;
  final Session? session;
  final Approval? approval;
  final Telemetry? telemetry;

  /// spawn 前审批：未注入或通过返回 true。拒绝时返回 false。
  Future<bool> checkSpawnApproval({
    required String name,
    required List<String> tools,
  }) async {
    if (approval == null) return true;
    return _guarded(_ApprovalKind.spawn, name, tools);
  }

  /// interrupt 前审批。
  Future<bool> checkInterruptApproval({required String teammateId}) async {
    if (approval == null) return true;
    return _guarded(_ApprovalKind.interrupt, teammateId, const <String>[]);
  }

  /// spawn 成功后：记录任务 / 会话 / 遥测；返回外部任务 id（可空）。
  Future<String?> onSpawn({
    required String teammateId,
    required String name,
    required String leadId,
    required List<String> tools,
  }) async {
    final String? taskId = await taskTracker?.beginMember(
      teammateId: teammateId,
      name: name,
      leadId: leadId,
    );
    _emit('team.spawn', <String, Object?>{
      'teammateId': teammateId,
      'name': name,
      'tools': tools,
      if (taskId != null) 'taskId': taskId,
    });
    _append('team/spawned', <String, Object?>{
      'teammateId': teammateId,
      'name': name,
    });
    return taskId;
  }

  /// send 时：记录会话 / 遥测。
  void onSend({
    required String from,
    required String to,
    required String message,
  }) {
    _emit('team.send', <String, Object?>{'from': from, 'to': to});
    _append('team/message_sent', <String, Object?>{'from': from, 'to': to});
  }

  /// createTask 时。
  void onTaskCreated({
    required String taskId,
    required String description,
    String? assigneeId,
  }) {
    _emit('team.task.create', <String, Object?>{
      'taskId': taskId,
      'description': description,
      if (assigneeId != null) 'assigneeId': assigneeId,
    });
    _append('team/task_created', <String, Object?>{'taskId': taskId});
  }

  /// remove 时：按状态落定外部任务。
  Future<void> onRemove({
    required String teammateId,
    required bool completed,
    Object? result,
    Object? error,
  }) async {
    if (completed) {
      await taskTracker?.completeMember(teammateId, result: result);
      _emit('team.remove',
          <String, Object?>{'teammateId': teammateId, 'outcome': 'completed'});
    } else {
      await taskTracker?.failMember(teammateId, error: error);
      _emit('team.remove',
          <String, Object?>{'teammateId': teammateId, 'outcome': 'failed'});
    }
    _append('team/removed', <String, Object?>{
      'teammateId': teammateId,
      'completed': completed,
    });
  }

  Future<bool> _guarded(
      _ApprovalKind kind, String label, List<String> tools) async {
    final ApprovalRequest req = ApprovalRequest(
      id: 'team-${kind.name}-${DateTime.now().microsecondsSinceEpoch}',
      toolName: kind.tool,
      arguments: <String, Object?>{'label': label, 'tools': tools},
      description:
          kind == _ApprovalKind.spawn ? '创建团队成员「$label」' : '中断成员「$label」',
    );
    try {
      final bool ok = await approval!.request(req);
      if (!ok) {
        _emit('team.${kind.name}.denied', <String, Object?>{'id': req.id});
      }
      return ok;
    } catch (error) {
      _emit('team.${kind.name}.error', <String, Object?>{'error': '$error'});
      return false;
    }
  }

  void _emit(String name, Map<String, Object?> data) {
    try {
      telemetry?.emit(TelemetryEvent(name, data: data));
    } catch (_) {}
  }

  void _append(String type, Map<String, Object?> data) {
    try {
      session?.append(type, data: data);
    } catch (_) {}
  }
}

enum _ApprovalKind {
  spawn('spawn_teammate'),
  interrupt('interrupt_agent');

  const _ApprovalKind(this.tool);
  final String tool;
}
