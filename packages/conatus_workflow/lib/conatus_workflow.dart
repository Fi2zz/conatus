/// conatus_workflow：编排引擎（实验性）。
///
/// 本包处于早期探索阶段，API 可能在没有 major 版本号变更的情况下发生
/// 破坏性改动。请勿在生产环境依赖它。
///
/// 已落地：流程定义词汇 —— [WorkflowDefinition] / [WorkflowInput] /
/// [WorkflowNode] 三种节点（[ToolNode] / [AgentNode] / [SubWorkflowNode]），
/// 声明式 JSON 序列化（[WorkflowNode.fromJson] 按 `type` 分派，非法输入
/// 抛 [WorkflowException]）。执行引擎（DAG 遍历 / 暂停恢复 / 工具层）
/// 尚未实现，见 `.handoffs/HANDOFF-7.md`。
library;

export 'src/definition.dart' show WorkflowDefinition, WorkflowInput;
export 'src/errors.dart' show WorkflowException;
export 'src/node.dart' show AgentNode, SubWorkflowNode, ToolNode, WorkflowNode;
