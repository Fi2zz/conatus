/// 编排引擎的词汇：接口、事件与节点执行口。
///
/// [WorkflowEngine] 是编排入口，[WorkflowEvent] 是其变更流的事件类型。
/// [NodeExecutor] 是引擎的节点执行口：工具 / 成员 / 子流程的具体执行
/// （第 5 步的 executor）经此注入，引擎只负责 DAG 遍历与状态机。
library;

import 'definition.dart';
import 'node.dart';
import 'run.dart';

/// 节点执行函数。执行单个节点并返回节点输出；抛异常视为节点失败。
typedef NodeExecutor = Future<Object?> Function(
  WorkflowNode node,
  WorkflowRun run,
);

/// 编排引擎。
abstract class WorkflowEngine {
  /// 注册流程定义。
  Future<void> register(WorkflowDefinition definition);

  /// 注销流程定义。
  Future<void> unregister(String name);

  /// 列出已注册的流程。
  List<WorkflowDefinition> get definitions;

  /// 查询流程定义。
  WorkflowDefinition? definition(String name);

  /// 启动一次执行。子流程节点经 [parentRunId] 挂到调用它的运行，
  /// 用于递归深度限制。
  Future<WorkflowRun> start(
    String workflowName, {
    Map<String, Object?> inputs = const <String, Object?>{},
    String? runId,
    String? parentRunId,
  });

  /// 查询运行。
  WorkflowRun? run(String runId);

  /// 列出所有运行。
  List<WorkflowRun> get runs;

  /// 暂停运行。当前节点完成后暂停。
  Future<void> pause(String runId);

  /// 恢复运行。
  Future<WorkflowRun> resume(String runId);

  /// 重跑指定节点。级联重置下游节点。
  Future<WorkflowRun> rerun(String runId, String nodeId);

  /// 取消运行。
  Future<void> cancel(String runId);

  /// 变更流。
  Stream<WorkflowEvent> get changes;

  /// 释放资源。
  void dispose();
}

/// 工作流事件。
sealed class WorkflowEvent {
  const WorkflowEvent();
}

/// 流程注册成功。
class WorkflowRegistered extends WorkflowEvent {
  const WorkflowRegistered(this.definition);

  final WorkflowDefinition definition;
}

/// 运行开始。
class RunStarted extends WorkflowEvent {
  const RunStarted(this.run);

  final WorkflowRun run;
}

/// 节点开始执行。
class RunNodeStarted extends WorkflowEvent {
  const RunNodeStarted(this.runId, this.nodeId);

  final String runId;
  final String nodeId;
}

/// 节点完成。
class RunNodeCompleted extends WorkflowEvent {
  const RunNodeCompleted(this.runId, this.nodeId, this.outputs);

  final String runId;
  final String nodeId;
  final Object? outputs;
}

/// 节点失败。
class RunNodeFailed extends WorkflowEvent {
  const RunNodeFailed(this.runId, this.nodeId, this.error);

  final String runId;
  final String nodeId;
  final Object? error;
}

/// 运行完成。
class RunCompleted extends WorkflowEvent {
  const RunCompleted(this.run);

  final WorkflowRun run;
}

/// 运行失败。
class RunFailed extends WorkflowEvent {
  const RunFailed(this.runId, this.error);

  final String runId;
  final Object? error;
}
