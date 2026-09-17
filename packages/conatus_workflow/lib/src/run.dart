/// 一次流程执行。
///
/// [WorkflowRun] 是流程的一次运行实例，持有节点运行记录
/// （[RunNode]）。`readyNodes` 返回引擎标记为可执行的节点（ready
/// 状态由引擎按流程定义维护，节点本身不记录依赖关系）。
///
/// [outputs] 与文档 4.2 的一处差异：运行实例不持有流程定义，无法自行
/// 按声明提取输出，因此引擎在运行完成时经 [WorkflowRun.copyWith] 写入
/// 该字段，getter 由字段提供。
library;

import 'errors.dart';
import 'json_helpers.dart';
import 'run_node.dart';
import 'status.dart';

/// 一次流程执行。
class WorkflowRun {
  const WorkflowRun({
    required this.id,
    required this.workflowName,
    required this.workflowVersion,
    required this.status,
    required this.inputs,
    required this.nodes,
    required this.createdAt,
    this.outputs = const <String, Object?>{},
    this.startedAt,
    this.finishedAt,
    this.error,
  });

  /// copyWith 未传参时的哨兵，区分「不修改」与「置 null」。
  static const Object _unset = Object();

  /// 运行唯一 ID。
  final String id;

  /// 流程名。
  final String workflowName;

  /// 流程版本。
  final int workflowVersion;

  /// 运行状态。
  final RunStatus status;

  /// 运行输入。
  final Map<String, Object?> inputs;

  /// 节点运行记录。key 是节点 ID。
  final Map<String, RunNode> nodes;

  /// 输出。引擎在运行完成时按流程定义声明写入。
  final Map<String, Object?> outputs;

  /// 创建时间。
  final DateTime createdAt;

  /// 开始时间。
  final DateTime? startedAt;

  /// 结束时间。
  final DateTime? finishedAt;

  /// 错误（status == failed 时可选）。
  final Object? error;

  /// 可执行节点（引擎标记为 ready 的节点）。
  List<String> get readyNodes => nodes.entries
      .where(
        (MapEntry<String, RunNode> entry) =>
            entry.value.status == RunNodeStatus.ready,
      )
      .map((MapEntry<String, RunNode> entry) => entry.key)
      .toList();

  /// 返回更新后的副本；[startedAt] / [finishedAt] / [error] 传 null
  /// 表示清除；[outputs] 传 null 表示不修改（想置空请传空 map）。
  WorkflowRun copyWith({
    RunStatus? status,
    Map<String, RunNode>? nodes,
    Map<String, Object?>? outputs,
    Object? startedAt = _unset,
    Object? finishedAt = _unset,
    Object? error = _unset,
  }) {
    return WorkflowRun(
      id: id,
      workflowName: workflowName,
      workflowVersion: workflowVersion,
      status: status ?? this.status,
      inputs: inputs,
      nodes: nodes ?? this.nodes,
      outputs: outputs ?? this.outputs,
      createdAt: createdAt,
      startedAt: identical(startedAt, _unset)
          ? this.startedAt
          : startedAt as DateTime?,
      finishedAt: identical(finishedAt, _unset)
          ? this.finishedAt
          : finishedAt as DateTime?,
      error: identical(error, _unset) ? this.error : error,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'workflowName': workflowName,
        'workflowVersion': workflowVersion,
        'status': status.name,
        'inputs': inputs,
        'nodes': nodes.map(
          (String nodeId, RunNode node) =>
              MapEntry<String, Object?>(nodeId, node.toJson()),
        ),
        'outputs': outputs,
        'createdAt': createdAt.toIso8601String(),
        'startedAt': startedAt?.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'error': error,
      };

  factory WorkflowRun.fromJson(Map<String, Object?> json) => WorkflowRun(
        id: requiredString(json, 'id'),
        workflowName: requiredString(json, 'workflowName'),
        workflowVersion: requiredInt(json, 'workflowVersion'),
        status: RunStatus.values.asNameMap()['${json['status']}'] ??
            RunStatus.pending,
        inputs: requiredStringMap(json, 'inputs'),
        nodes: _parseRunNodes(json['nodes']),
        outputs: optionalStringMap(json, 'outputs'),
        createdAt: requiredDateTime(json, 'createdAt'),
        startedAt: optionalDateTime(json, 'startedAt'),
        finishedAt: optionalDateTime(json, 'finishedAt'),
        error: json['error'],
      );
}

/// 解析节点运行记录表；缺失抛 [WorkflowException]。
Map<String, RunNode> _parseRunNodes(Object? raw) {
  if (raw == null) {
    throw const WorkflowException('missing-field', '缺少必填字段: nodes');
  }
  if (raw is! Map) {
    throw const WorkflowException('bad-type', '字段类型错误: nodes');
  }
  return raw.map((Object? key, Object? value) {
    if (key is! String) {
      throw const WorkflowException('bad-type', '字段类型错误: nodes');
    }
    if (value is! Map) {
      throw const WorkflowException('bad-type', '字段类型错误: nodes');
    }
    return MapEntry<String, RunNode>(
      key,
      RunNode.fromJson(Map<String, Object?>.from(value)),
    );
  });
}
