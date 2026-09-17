/// 流程节点的词汇：三种节点类型。
///
/// [WorkflowNode] 是 sealed 基类，三种节点 —— [ToolNode]（调用已注册
/// 工具）/ [AgentNode]（创建团队成员执行任务）/ [SubWorkflowNode]
/// （调用另一个流程）—— 共享 `id` / `dependsOn` / `when`。JSON 序列化
/// 用 `type` 字段区分节点种类，反序列化按 [WorkflowNode.fromJson] 分派。
/// `{{nodeId.output}}` 形式的引用只作为字符串原样保存，解析是引擎的职责。
library;

import 'errors.dart';
import 'json_helpers.dart';

/// 按 `type` 字段分派的节点反序列化表。
final Map<String, WorkflowNode Function(Map<String, Object?>)> _nodeFactories =
    <String, WorkflowNode Function(Map<String, Object?>)>{
  'tool': ToolNode.fromJson,
  'agent': AgentNode.fromJson,
  'subworkflow': SubWorkflowNode.fromJson,
};

/// 流程节点。三种类型：tool / agent / subworkflow。
sealed class WorkflowNode {
  const WorkflowNode({
    required this.id,
    required this.dependsOn,
    this.when,
  });

  /// 节点唯一 ID。
  final String id;

  /// 依赖哪些节点。全部完成才能执行。
  final List<String> dependsOn;

  /// 条件表达式。为 null 时无条件执行。
  /// 表达式只能引用已完成节点的输出。
  final String? when;

  Map<String, Object?> toJson();

  /// 按 `type` 字段反序列化；未知类型抛 [WorkflowException]。
  factory WorkflowNode.fromJson(Map<String, Object?> json) {
    final rawType = json['type'];
    final node = _nodeFactories[rawType is String ? rawType : '']?.call(json);
    if (node == null) {
      throw WorkflowException('unknown-node-type', '未知节点类型: $rawType');
    }
    return node;
  }
}

/// 工具节点：调用一个已注册的工具。
class ToolNode extends WorkflowNode {
  const ToolNode({
    required super.id,
    required super.dependsOn,
    required this.tool,
    this.arguments = const <String, Object?>{},
    super.when,
  });

  /// 工具名。
  final String tool;

  /// 参数。值可以是字面量，也可以是 `{{nodeId.output}}` 形式的引用。
  final Map<String, Object?> arguments;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': 'tool',
        'id': id,
        'dependsOn': dependsOn,
        'when': when,
        'tool': tool,
        'arguments': arguments,
      };

  factory ToolNode.fromJson(Map<String, Object?> json) => ToolNode(
        id: requiredString(json, 'id'),
        dependsOn: requiredStringList(json, 'dependsOn'),
        tool: requiredString(json, 'tool'),
        arguments: optionalStringMap(json, 'arguments'),
        when: optionalString(json, 'when'),
      );
}

/// Agent 节点：创建一个团队成员执行任务。
class AgentNode extends WorkflowNode {
  const AgentNode({
    required super.id,
    required super.dependsOn,
    required this.task,
    this.name,
    this.tools,
    this.systemPrompt,
    super.when,
  });

  /// 任务描述。
  final String task;

  /// 成员名字。缺省用节点 ID。
  final String? name;

  /// 成员可用的工具白名单。
  final List<String>? tools;

  /// 成员的角色定义。
  final String? systemPrompt;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': 'agent',
        'id': id,
        'dependsOn': dependsOn,
        'when': when,
        'task': task,
        'name': name,
        'tools': tools,
        'systemPrompt': systemPrompt,
      };

  factory AgentNode.fromJson(Map<String, Object?> json) => AgentNode(
        id: requiredString(json, 'id'),
        dependsOn: requiredStringList(json, 'dependsOn'),
        task: requiredString(json, 'task'),
        name: optionalString(json, 'name'),
        tools: nullableStringList(json, 'tools'),
        systemPrompt: optionalString(json, 'systemPrompt'),
        when: optionalString(json, 'when'),
      );
}

/// 子流程节点：调用另一个流程。
class SubWorkflowNode extends WorkflowNode {
  const SubWorkflowNode({
    required super.id,
    required super.dependsOn,
    required this.workflow,
    this.inputs = const <String, Object?>{},
    super.when,
  });

  /// 子流程名。
  final String workflow;

  /// 子流程输入。
  final Map<String, Object?> inputs;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': 'subworkflow',
        'id': id,
        'dependsOn': dependsOn,
        'when': when,
        'workflow': workflow,
        'inputs': inputs,
      };

  factory SubWorkflowNode.fromJson(Map<String, Object?> json) =>
      SubWorkflowNode(
        id: requiredString(json, 'id'),
        dependsOn: requiredStringList(json, 'dependsOn'),
        workflow: requiredString(json, 'workflow'),
        inputs: optionalStringMap(json, 'inputs'),
        when: optionalString(json, 'when'),
      );
}
