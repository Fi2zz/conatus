/// Workflow 运行时 hooks：聚合 4 条可选 seam（任务追踪 / 会话日志 /
/// 审批 / 遥测）。
///
/// [WorkflowHooks] 被引擎在每个关键节点调用，所有 seam 均可选——未注入
/// 时对应行为是 no-op。seam 异常被捕获并降级，不污染主流程。
/// 会话日志以 `workflow/run` 事件持久化运行图快照（append-only，
/// 恢复时折叠最后一个，见 [restoreWorkflowRun]）。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_tasks/conatus_tasks.dart';

import 'definition.dart';
import 'node.dart';
import 'run.dart';

/// 运行图会话事件类型。
const String kWorkflowRunEvent = 'workflow/run';

/// Workflow 运行时 hook 聚合。
class WorkflowHooks {
  WorkflowHooks({
    this.taskCenter,
    this.session,
    this.approval,
    this.telemetry,
    this.tools,
    this.definitionOf,
  });

  final TaskCenter? taskCenter;
  final Session? session;
  final Approval? approval;
  final Telemetry? telemetry;
  final ToolRegistry? tools;
  final WorkflowDefinition? Function(String name)? definitionOf;

  /// 节点启动时创建的外部任务 id（key 为 `runId/nodeId`）。
  final Map<String, String> _taskIds = <String, String>{};

  /// 注册流程。
  void onRegistered(WorkflowDefinition definition) {
    _emit('workflow.registered', <String, Object?>{
      'name': definition.name,
      'version': definition.version,
    });
  }

  /// 运行开始。
  void onRunStarted(WorkflowRun run) {
    _emit('workflow.run.started', <String, Object?>{'runId': run.id});
    _appendRun(run);
  }

  /// 运行暂停。
  void onRunPaused(WorkflowRun run) {
    _emit('workflow.run.paused', <String, Object?>{'runId': run.id});
    _appendRun(run);
  }

  /// 运行恢复。
  void onRunResumed(WorkflowRun run) {
    _emit('workflow.run.resumed', <String, Object?>{'runId': run.id});
    _appendRun(run);
  }

  /// 运行完成。
  void onRunCompleted(WorkflowRun run) {
    _emit('workflow.run.completed', <String, Object?>{'runId': run.id});
    _appendRun(run);
  }

  /// 运行失败。
  void onRunFailed(WorkflowRun run) {
    _emit('workflow.run.failed', <String, Object?>{'runId': run.id});
    _appendRun(run);
  }

  /// 节点启动：创建外部任务（kind: custom）。
  Future<void> onNodeStarted(WorkflowRun run, String nodeId) async {
    String? taskId;
    try {
      final task = await taskCenter?.create(
        kind: TaskKind.custom,
        description: '流程节点: $nodeId',
        metadata: <String, Object?>{'runId': run.id, 'nodeId': nodeId},
      );
      taskId = task?.id;
      if (taskId != null) _taskIds['${run.id}/$nodeId'] = taskId;
    } catch (error) {
      _emit('workflow.tracker.error', <String, Object?>{
        'operation': 'create',
        'error': '$error',
      });
    }
    _emit('workflow.node.started', <String, Object?>{
      'runId': run.id,
      'nodeId': nodeId,
      if (taskId != null) 'taskId': taskId,
    });
    _appendRun(run);
  }

  /// 节点完成：落定外部任务。
  Future<void> onNodeCompleted(WorkflowRun run, String nodeId) async {
    final taskId = _taskIds['${run.id}/$nodeId'];
    if (taskId != null) {
      try {
        await taskCenter?.update(
          taskId,
          status: TaskStatus.completed,
          result: run.nodes[nodeId]?.outputs,
        );
      } catch (error) {
        _emit('workflow.tracker.error', <String, Object?>{
          'operation': 'complete',
          'error': '$error',
        });
      }
    }
    _emit('workflow.node.completed', <String, Object?>{
      'runId': run.id,
      'nodeId': nodeId,
    });
    _appendRun(run);
  }

  /// 节点失败：落定外部任务。
  Future<void> onNodeFailed(
    WorkflowRun run,
    String nodeId,
    Object? error,
  ) async {
    final taskId = _taskIds['${run.id}/$nodeId'];
    if (taskId != null) {
      try {
        await taskCenter?.update(
          taskId,
          status: TaskStatus.failed,
          error: error,
        );
      } catch (trackerError) {
        _emit('workflow.tracker.error', <String, Object?>{
          'operation': 'fail',
          'error': '$trackerError',
        });
      }
    }
    _emit('workflow.node.failed', <String, Object?>{
      'runId': run.id,
      'nodeId': nodeId,
    });
    _appendRun(run);
  }

  /// 节点跳过。
  void onNodeSkipped(WorkflowRun run, String nodeId) {
    _emit('workflow.node.skipped', <String, Object?>{
      'runId': run.id,
      'nodeId': nodeId,
    });
    _appendRun(run);
  }

  /// 节点执行前审批：低风险或未注入审批直接通过。
  Future<bool> checkApproval(WorkflowNode node) async {
    final risk = _riskOf(node, <String>{});
    if (risk == ToolRisk.low) return true;
    if (approval == null) return true;
    final request = ApprovalRequest(
      id: 'workflow-node-${DateTime.now().microsecondsSinceEpoch}',
      toolName: node is ToolNode ? node.tool : 'workflow_node',
      arguments: <String, Object?>{'nodeId': node.id},
      description: '流程节点「${node.id}」需要审批',
    );
    try {
      return await approval!.request(request);
    } catch (_) {
      return false;
    }
  }

  /// 节点风险：工具取自身风险；成员取工具白名单最高风险；子流程递归。
  ToolRisk _riskOf(WorkflowNode node, Set<String> visited) {
    return switch (node) {
      ToolNode() => tools?.get(node.tool)?.riskLevel ?? ToolRisk.low,
      AgentNode() => _maxToolRisk(node.tools ?? const <String>[]),
      SubWorkflowNode() => _subRisk(node, visited),
    };
  }

  ToolRisk _subRisk(SubWorkflowNode node, Set<String> visited) {
    if (!visited.add(node.workflow)) return ToolRisk.low;
    final sub = definitionOf?.call(node.workflow);
    if (sub == null) return ToolRisk.low;
    var max = ToolRisk.low;
    for (final WorkflowNode child in sub.nodes) {
      final risk = _riskOf(child, visited);
      if (risk.index > max.index) max = risk;
    }
    return max;
  }

  ToolRisk _maxToolRisk(List<String> toolNames) {
    var max = ToolRisk.low;
    for (final String name in toolNames) {
      final risk = tools?.get(name)?.riskLevel ?? ToolRisk.low;
      if (risk.index > max.index) max = risk;
    }
    return max;
  }

  void _emit(String name, Map<String, Object?> data) {
    try {
      telemetry?.emit(TelemetryEvent(name, data: data));
    } catch (_) {}
  }

  void _appendRun(WorkflowRun run) {
    try {
      session?.append(kWorkflowRunEvent, data: run.toJson());
    } catch (_) {}
  }
}

/// 从会话事件折叠出最后一次运行图快照。
WorkflowRun? restoreWorkflowRun(Session session) {
  WorkflowRun? latest;
  for (final SessionEvent event in session.ownEvents) {
    if (event.type != kWorkflowRunEvent) continue;
    final data = event.data;
    if (data is! Map) continue;
    latest = WorkflowRun.fromJson(Map<String, Object?>.from(data));
  }
  return latest;
}
