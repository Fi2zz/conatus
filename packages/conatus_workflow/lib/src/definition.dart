/// 流程定义的词汇：输入声明与定义本体。
///
/// [WorkflowDefinition] 是声明式、可序列化的流程定义，[WorkflowInput]
/// 声明运行输入。`WorkflowDefinition.fromJson` 对必填字段缺失或类型
/// 错误抛 [WorkflowException]（`missing-field` / `bad-type`）。
library;

import 'errors.dart';
import 'json_helpers.dart';
import 'node.dart';

/// 流程输入声明。
class WorkflowInput {
  const WorkflowInput({
    required this.name,
    required this.type,
    this.required = false,
    this.defaultValue,
    this.description = '',
  });

  final String name;

  /// 'string' / 'integer' / 'boolean' / 'array' / 'object'。
  final String type;

  final bool required;
  final Object? defaultValue;
  final String description;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'type': type,
        'required': required,
        'defaultValue': defaultValue,
        'description': description,
      };

  factory WorkflowInput.fromJson(Map<String, Object?> json) => WorkflowInput(
        name: requiredString(json, 'name'),
        type: requiredString(json, 'type'),
        required: json['required'] == true,
        defaultValue: json['defaultValue'],
        description: optionalString(json, 'description') ?? '',
      );
}

/// 流程定义。声明式，可序列化。
class WorkflowDefinition {
  const WorkflowDefinition({
    required this.name,
    required this.version,
    required this.nodes,
    this.description = '',
    this.inputs = const <WorkflowInput>[],
    this.outputs = const <String>[],
    this.metadata = const <String, Object?>{},
  });

  /// 流程名。唯一标识。
  final String name;

  /// 流程版本。用于演进管理。
  final int version;

  /// 流程描述。
  final String description;

  /// 输入声明。
  final List<WorkflowInput> inputs;

  /// 输出节点 ID 列表。
  final List<String> outputs;

  /// 节点列表。
  final List<WorkflowNode> nodes;

  /// 元数据。可放作者、标签等。
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'version': version,
        'description': description,
        'inputs': inputs.map((WorkflowInput input) => input.toJson()).toList(),
        'outputs': outputs,
        'metadata': metadata,
        'nodes': nodes.map((WorkflowNode node) => node.toJson()).toList(),
      };

  factory WorkflowDefinition.fromJson(Map<String, Object?> json) =>
      WorkflowDefinition(
        name: requiredString(json, 'name'),
        version: requiredInt(json, 'version'),
        nodes: _parseNodes(json['nodes']),
        description: optionalString(json, 'description') ?? '',
        inputs: _parseInputs(json['inputs']),
        outputs: optionalStringList(json, 'outputs'),
        metadata: optionalStringMap(json, 'metadata'),
      );
}

/// 解析节点列表；缺失抛 [WorkflowException]。
List<WorkflowNode> _parseNodes(Object? raw) {
  if (raw == null) {
    throw const WorkflowException('missing-field', '缺少必填字段: nodes');
  }
  if (raw is! List) {
    throw const WorkflowException('bad-type', '字段类型错误: nodes');
  }
  return raw.map((Object? item) {
    if (item is Map) {
      return WorkflowNode.fromJson(Map<String, Object?>.from(item));
    }
    throw const WorkflowException('bad-type', '字段类型错误: nodes');
  }).toList();
}

/// 解析输入列表；缺失降级为空列表。
List<WorkflowInput> _parseInputs(Object? raw) {
  if (raw == null) return const <WorkflowInput>[];
  if (raw is! List) {
    throw const WorkflowException('bad-type', '字段类型错误: inputs');
  }
  return raw.map((Object? item) {
    if (item is Map) {
      return WorkflowInput.fromJson(Map<String, Object?>.from(item));
    }
    throw const WorkflowException('bad-type', '字段类型错误: inputs');
  }).toList();
}
