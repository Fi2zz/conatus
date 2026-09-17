/// DAG 遍历的纯函数：可执行节点、下游节点与终态判定。
///
/// 不持有状态，供引擎执行循环复用。依赖语义：
/// - 依赖满足 = 上游节点全部 completed 或 skipped（终态即可，不阻塞下游）；
/// - 上游 failed 的节点不会被标记为可执行，运行整体判失败。
library;

import 'definition.dart';
import 'node.dart';
import 'run.dart';
import 'status.dart';

/// 节点依赖是否全部满足（上游全部 completed 或 skipped，failed 不算）。
bool depsMet(WorkflowNode node, WorkflowRun run) {
  return node.dependsOn.every((String dep) {
    final depNode = run.nodes[dep];
    if (depNode == null) return false;
    return depNode.status == RunNodeStatus.completed ||
        depNode.status == RunNodeStatus.skipped;
  });
}

/// 找出当前可执行的节点 ID：仍为 pending 且依赖全部满足。
List<String> findReadyNodeIds(WorkflowDefinition definition, WorkflowRun run) {
  return definition.nodes
      .where(
        (WorkflowNode node) =>
            run.nodes[node.id]?.status == RunNodeStatus.pending &&
            depsMet(node, run),
      )
      .toList()
      .map((WorkflowNode node) => node.id)
      .toList();
}

/// 找出直接或间接依赖 [nodeId] 的节点 ID（含自身），用于重跑级联重置。
List<String> findDownstreamNodeIds(
  WorkflowDefinition definition,
  String nodeId,
) {
  final result = <String>{nodeId};
  var frontier = <String>[nodeId];
  while (frontier.isNotEmpty) {
    final next = <String>[];
    for (final WorkflowNode node in definition.nodes) {
      if (node.dependsOn.any(frontier.contains) && result.add(node.id)) {
        next.add(node.id);
      }
    }
    frontier = next;
  }
  return result.toList();
}
