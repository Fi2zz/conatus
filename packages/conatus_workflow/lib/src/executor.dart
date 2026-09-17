/// 真实节点执行器：工具 / 成员 / 子流程。
///
/// [buildNodeExecutor] 把引擎的 [NodeExecutor] 口接到运行时依赖：
/// - [ToolNode] → [ToolRegistry.call]（工具未注册或失败抛 [WorkflowException]）；
/// - [AgentNode] → [AgentTeam.spawn] + [AgentTeam.ask] + 完成后移除成员；
/// - [SubWorkflowNode] → [WorkflowEngine.start] 递归执行（深度受限）。
library;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_team/conatus_team.dart';

import 'engine.dart';
import 'errors.dart';
import 'node.dart';
import 'refs.dart';
import 'run.dart';
import 'status.dart';

/// 构造真实节点执行器。
///
/// [engineOf] 延迟解析引擎（执行器与引擎互相引用，装配方用
/// `engineOf: () => engine` 解开循环）。
NodeExecutor buildNodeExecutor({
  required WorkflowEngine Function() engineOf,
  required AgentTeam team,
  required ToolRegistry tools,
  int maxDepth = 5,
}) {
  return (WorkflowNode node, WorkflowRun run) {
    return switch (node) {
      ToolNode() => _runTool(tools, node, run),
      AgentNode() => _runAgent(team, node),
      SubWorkflowNode() => _runSubWorkflow(engineOf(), node, run, maxDepth),
    };
  };
}

Future<Object?> _runTool(
  ToolRegistry tools,
  ToolNode node,
  WorkflowRun run,
) async {
  if (tools.get(node.tool) == null) {
    throw WorkflowException('unknown-tool', '未注册的工具: ${node.tool}');
  }
  final result = await tools.call(
    ToolCall(
      name: node.tool,
      arguments: resolveArguments(node.arguments, run),
    ),
  );
  if (result.isError) {
    throw WorkflowException(
      'tool-failed',
      '工具 ${node.tool} 失败: ${result.content}',
    );
  }
  return result.value ?? result.content;
}

Future<Object?> _runAgent(AgentTeam team, AgentNode node) async {
  final mate = await team.spawn(
    name: node.name ?? node.id,
    tools: node.tools,
    systemPrompt: node.systemPrompt,
  );
  try {
    return await team.ask(mate.id, node.task);
  } finally {
    await team.remove(mate.id);
  }
}

Future<Object?> _runSubWorkflow(
  WorkflowEngine engine,
  SubWorkflowNode node,
  WorkflowRun parent,
  int maxDepth,
) async {
  final depth = _runDepth(engine, parent);
  if (depth >= maxDepth) {
    throw WorkflowException('max-depth', '子流程嵌套超过上限 $maxDepth');
  }
  final child = await engine.start(
    node.workflow,
    inputs: resolveArguments(node.inputs, parent),
    parentRunId: parent.id,
  );
  await _waitTerminal(engine, child.id);
  final result = engine.run(child.id)!;
  if (result.status == RunStatus.failed) {
    throw WorkflowException(
      'subworkflow-failed',
      '子流程 ${node.workflow} 失败: ${result.error}',
    );
  }
  return result.outputs;
}

/// 沿 parentRunId 链计算运行深度。
int _runDepth(WorkflowEngine engine, WorkflowRun run) {
  var depth = 0;
  var current = run;
  while (current.parentRunId != null) {
    depth++;
    final parent = engine.run(current.parentRunId!);
    if (parent == null) break;
    current = parent;
  }
  return depth;
}

/// 等待子流程进入终态。
Future<void> _waitTerminal(WorkflowEngine engine, String runId) async {
  final deadline = DateTime.now().add(const Duration(minutes: 5));
  while (!(engine.run(runId)?.status.isTerminal ?? false)) {
    if (DateTime.now().isAfter(deadline)) {
      throw WorkflowException('subworkflow-timeout', '子流程等待超时: $runId');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
