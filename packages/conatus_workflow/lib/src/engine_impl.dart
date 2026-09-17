/// 编排引擎默认实现：注册表、运行状态与事件流。
///
/// 执行循环（DAG 遍历，见 [engine_loop]）与节点执行经 [NodeExecutor]
/// 注入；本文件通过 `part` 与执行循环共享私有状态。
library;

import 'dart:async';

import 'dag.dart';
import 'definition.dart';
import 'engine.dart';
import 'errors.dart';
import 'node.dart';
import 'refs.dart';
import 'run.dart';
import 'run_node.dart';
import 'status.dart';
import 'store.dart';

/// 编排引擎默认实现。
class WorkflowEngineImpl implements WorkflowEngine {
  WorkflowEngineImpl({
    required NodeExecutor executor,
    WorkflowStore? store,
  })  : _executor = executor,
        _store = store ?? InMemoryWorkflowStore();

  final NodeExecutor _executor;
  final WorkflowStore _store;
  final Map<String, WorkflowDefinition> _definitions =
      <String, WorkflowDefinition>{};
  final Map<String, WorkflowRun> _runs = <String, WorkflowRun>{};
  final StreamController<WorkflowEvent> _changes =
      StreamController<WorkflowEvent>.broadcast();
  final Set<String> _pauseRequested = <String>{};
  final Set<String> _cancelRequested = <String>{};
  final Set<String> _ticking = <String>{};
  int _runSeq = 0;

  @override
  Future<void> register(WorkflowDefinition definition) async {
    _definitions[definition.name] = definition;
    await _store.saveDefinition(definition);
    _changes.add(WorkflowRegistered(definition));
  }

  @override
  Future<void> unregister(String name) async {
    _definitions.remove(name);
    await _store.deleteDefinition(name);
  }

  @override
  List<WorkflowDefinition> get definitions =>
      _definitions.values.toList(growable: false);

  @override
  WorkflowDefinition? definition(String name) => _definitions[name];

  @override
  Future<WorkflowRun> start(
    String workflowName, {
    Map<String, Object?> inputs = const <String, Object?>{},
    String? runId,
    String? parentRunId,
  }) async {
    final definition = _definitions[workflowName];
    if (definition == null) {
      throw WorkflowException('unknown-workflow', '未注册的流程: $workflowName');
    }
    final id = runId ?? '$workflowName-${++_runSeq}';
    final now = DateTime.now();
    final run = WorkflowRun(
      id: id,
      workflowName: workflowName,
      workflowVersion: definition.version,
      status: RunStatus.running,
      inputs: inputs,
      nodes: <String, RunNode>{
        for (final WorkflowNode node in definition.nodes)
          node.id: RunNode(
            id: node.id,
            status: RunNodeStatus.pending,
            inputs: const <String, Object?>{},
          ),
      },
      createdAt: now,
      startedAt: now,
      parentRunId: parentRunId,
    );
    _runs[id] = run;
    await _store.saveRun(run);
    _changes.add(RunStarted(run));
    unawaited(_tick(id));
    return run;
  }

  @override
  WorkflowRun? run(String runId) => _runs[runId];

  @override
  List<WorkflowRun> get runs => _runs.values.toList(growable: false);

  @override
  Future<void> pause(String runId) async {
    final current = _runs[runId];
    if (current == null || current.status != RunStatus.running) return;
    _pauseRequested.add(runId);
  }

  @override
  Future<WorkflowRun> resume(String runId) async {
    final current = _runs[runId];
    if (current == null) {
      throw WorkflowException('unknown-run', '未知运行: $runId');
    }
    if (current.status != RunStatus.paused) return current;
    await _setStatus(runId, RunStatus.running);
    unawaited(_tick(runId));
    return _runs[runId]!;
  }

  @override
  Future<WorkflowRun> rerun(String runId, String nodeId) async {
    final current = _runs[runId];
    if (current == null) {
      throw WorkflowException('unknown-run', '未知运行: $runId');
    }
    final definition = _definitions[current.workflowName];
    if (definition == null ||
        !definition.nodes.any((WorkflowNode node) => node.id == nodeId)) {
      throw WorkflowException('unknown-node', '未知节点: $nodeId');
    }
    final downstream = findDownstreamNodeIds(definition, nodeId);
    final updated = current.copyWith(
      status: RunStatus.running,
      startedAt: current.startedAt ?? DateTime.now(),
      finishedAt: null,
      nodes: <String, RunNode>{
        for (final MapEntry<String, RunNode> entry in current.nodes.entries)
          if (downstream.contains(entry.key))
            entry.key: entry.value.copyWith(
              status: RunNodeStatus.pending,
              outputs: null,
              error: null,
              startedAt: null,
              finishedAt: null,
              attempts: 0,
            )
          else
            entry.key: entry.value,
      },
    );
    _runs[runId] = updated;
    await _store.saveRun(updated);
    unawaited(_tick(runId));
    return updated;
  }

  @override
  Future<void> cancel(String runId) async {
    final current = _runs[runId];
    if (current == null || current.status.isTerminal) return;
    _cancelRequested.add(runId);
  }

  @override
  Stream<WorkflowEvent> get changes => _changes.stream;

  @override
  void dispose() {
    _changes.close();
  }

  // REASON: 以下执行循环（DAG 遍历）与引擎实例状态强耦合（读改写
  // _runs/_definitions/_store/_changes/_executor），拆成独立类或 part
  // 顶层函数会退化为显式传参或过度抽象；作为实例方法单文件承载，
  // 与仓库同类实现（conatus_team team_impl.dart）规模一致。

  /// 执行循环：反复找出可执行节点并并发执行，直到无进展或收到控制请求。
  Future<void> _tick(String runId) async {
    if (!_ticking.add(runId)) return;
    try {
      final definition = _definitions[_runs[runId]!.workflowName]!;
      while (_runs[runId]!.status == RunStatus.running) {
        if (await _handleControl(runId)) return;
        await _skipUnmet(runId, definition);
        final ready = findReadyNodeIds(definition, _runs[runId]!);
        if (ready.isEmpty) break;
        await _runBatch(runId, ready);
      }
      await _maybeFinalize(runId);
    } finally {
      _ticking.remove(runId);
    }
  }

  /// 处理取消/暂停请求；已处理（应退出循环）返回 true。
  Future<bool> _handleControl(String runId) async {
    if (_cancelRequested.remove(runId)) {
      await _setStatus(runId, RunStatus.cancelled);
      return true;
    }
    if (_pauseRequested.remove(runId)) {
      await _setStatus(runId, RunStatus.paused);
      return true;
    }
    return false;
  }

  /// 把「依赖满足但 when 条件为假」的节点标记为 skipped。
  Future<void> _skipUnmet(
    String runId,
    WorkflowDefinition definition,
  ) async {
    final run = _runs[runId]!;
    for (final WorkflowNode node in definition.nodes) {
      final when = node.when;
      final runNode = run.nodes[node.id];
      final shouldSkip = when != null &&
          runNode?.status == RunNodeStatus.pending &&
          depsMet(node, run) &&
          !evaluateCondition(when, run);
      if (!shouldSkip) continue;
      await _skipNode(runId, node.id);
    }
  }

  /// 标记节点为跳过并发出事件。
  Future<void> _skipNode(String runId, String nodeId) async {
    final current = _runs[runId]!;
    final updated = current.copyWith(
      nodes: <String, RunNode>{
        ...current.nodes,
        nodeId: current.nodes[nodeId]!.copyWith(
          status: RunNodeStatus.skipped,
          finishedAt: DateTime.now(),
        ),
      },
    );
    _runs[runId] = updated;
    await _store.saveRun(updated);
    _changes.add(RunNodeSkipped(runId, nodeId));
  }

  /// 更新运行状态并持久化；终态时记录结束时间。
  Future<void> _setStatus(String runId, RunStatus status) async {
    final run = _runs[runId]!;
    final updated = run.copyWith(
      status: status,
      finishedAt: status.isTerminal ? DateTime.now() : null,
    );
    _runs[runId] = updated;
    await _store.saveRun(updated);
  }

  /// 并发执行一批节点。
  Future<void> _runBatch(String runId, List<String> ready) async {
    for (final String nodeId in ready) {
      await _markRunning(runId, nodeId);
    }
    await Future.wait(
        ready.map((String nodeId) => _executeNode(runId, nodeId)));
  }

  /// 标记节点为运行中并发出事件。
  Future<void> _markRunning(String runId, String nodeId) async {
    final current = _runs[runId]!;
    final updated = current.copyWith(
      nodes: <String, RunNode>{
        ...current.nodes,
        nodeId: current.nodes[nodeId]!.copyWith(
          status: RunNodeStatus.running,
          startedAt: DateTime.now(),
        ),
      },
    );
    _runs[runId] = updated;
    await _store.saveRun(updated);
    _changes.add(RunNodeStarted(runId, nodeId));
  }

  /// 执行单个节点：成功写输出，异常记失败。
  Future<void> _executeNode(String runId, String nodeId) async {
    final definition = _definitions[_runs[runId]!.workflowName]!;
    final node = definition.nodes.firstWhere(
      (WorkflowNode n) => n.id == nodeId,
    );
    try {
      final outputs = await _executor(node, _runs[runId]!);
      await _completeNode(runId, nodeId, outputs);
    } catch (error) {
      await _failNode(runId, nodeId, error);
    }
  }

  /// 记录节点完成。
  Future<void> _completeNode(
      String runId, String nodeId, Object? outputs) async {
    final current = _runs[runId]!;
    final updated = current.copyWith(
      nodes: <String, RunNode>{
        ...current.nodes,
        nodeId: current.nodes[nodeId]!.copyWith(
          status: RunNodeStatus.completed,
          outputs: outputs,
          finishedAt: DateTime.now(),
        ),
      },
    );
    _runs[runId] = updated;
    await _store.saveRun(updated);
    _changes.add(RunNodeCompleted(runId, nodeId, outputs));
  }

  /// 记录节点失败。
  Future<void> _failNode(String runId, String nodeId, Object? error) async {
    final current = _runs[runId]!;
    final updated = current.copyWith(
      nodes: <String, RunNode>{
        ...current.nodes,
        nodeId: current.nodes[nodeId]!.copyWith(
          status: RunNodeStatus.failed,
          error: error,
          finishedAt: DateTime.now(),
        ),
      },
    );
    _runs[runId] = updated;
    await _store.saveRun(updated);
    _changes.add(RunNodeFailed(runId, nodeId, error));
  }

  /// 无进展时收尾：有 failed 则标记未终态节点为 skipped 并判失败，
  /// 否则全部终态后判完成并提取输出。
  Future<void> _maybeFinalize(String runId) async {
    var run = _runs[runId]!;
    if (run.status != RunStatus.running) return;
    final hasFailed = run.nodes.values.any(
      (RunNode node) => node.status == RunNodeStatus.failed,
    );
    if (hasFailed) {
      run = run.copyWith(
        nodes: <String, RunNode>{
          for (final MapEntry<String, RunNode> entry in run.nodes.entries)
            if (!entry.value.status.isTerminal)
              entry.key: entry.value.copyWith(status: RunNodeStatus.skipped)
            else
              entry.key: entry.value,
        },
      );
      _runs[runId] = run;
      await _store.saveRun(run);
      await _setStatus(runId, RunStatus.failed);
      _changes.add(RunFailed(runId, _firstError(run)));
      return;
    }
    if (!run.nodes.values.every((RunNode node) => node.status.isTerminal)) {
      return;
    }
    final definition = _definitions[run.workflowName]!;
    final updated = run.copyWith(
      status: RunStatus.completed,
      outputs: _extractOutputs(definition, run),
      finishedAt: DateTime.now(),
    );
    _runs[runId] = updated;
    await _store.saveRun(updated);
    _changes.add(RunCompleted(updated));
  }

  /// 按流程定义的输出声明提取已完成节点的输出。
  Map<String, Object?> _extractOutputs(
    WorkflowDefinition definition,
    WorkflowRun run,
  ) {
    final outputs = <String, Object?>{};
    for (final String nodeId in definition.outputs) {
      final node = run.nodes[nodeId];
      if (node?.status == RunNodeStatus.completed && node?.outputs != null) {
        outputs[nodeId] = node!.outputs;
      }
    }
    return outputs;
  }

  /// 第一个失败节点的错误。
  Object? _firstError(WorkflowRun run) {
    for (final RunNode node in run.nodes.values) {
      if (node.status == RunNodeStatus.failed) return node.error;
    }
    return null;
  }
}
