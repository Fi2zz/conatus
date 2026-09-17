/// 节点运行记录。
///
/// [RunNode] 记录一次运行中单个节点的状态与结果。依赖关系不在节点上，
/// 由引擎按流程定义维护，节点只记录「何时开始 / 何时结束 / 输出 /
/// 错误 / 尝试次数」。
library;

import 'json_helpers.dart';
import 'status.dart';

/// 节点运行记录。
class RunNode {
  const RunNode({
    required this.id,
    required this.status,
    required this.inputs,
    this.outputs,
    this.error,
    this.startedAt,
    this.finishedAt,
    this.attempts = 0,
  });

  /// copyWith 未传参时的哨兵，区分「不修改」与「置 null」。
  static const Object _unset = Object();

  final String id;
  final RunNodeStatus status;
  final Map<String, Object?> inputs;
  final Object? outputs;
  final Object? error;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int attempts;

  /// 执行耗时；未开始时为 null，进行中按当前时间计算。
  Duration? get duration {
    if (startedAt == null) return null;
    return (finishedAt ?? DateTime.now()).difference(startedAt!);
  }

  /// 返回更新后的副本；[outputs] / [error] / [startedAt] / [finishedAt]
  /// 传 null 表示清除。
  RunNode copyWith({
    RunNodeStatus? status,
    Object? outputs = _unset,
    Object? error = _unset,
    Object? startedAt = _unset,
    Object? finishedAt = _unset,
    int? attempts,
  }) {
    return RunNode(
      id: id,
      status: status ?? this.status,
      inputs: inputs,
      outputs: identical(outputs, _unset) ? this.outputs : outputs,
      error: identical(error, _unset) ? this.error : error,
      startedAt: identical(startedAt, _unset)
          ? this.startedAt
          : startedAt as DateTime?,
      finishedAt: identical(finishedAt, _unset)
          ? this.finishedAt
          : finishedAt as DateTime?,
      attempts: attempts ?? this.attempts,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'status': status.name,
        'inputs': inputs,
        'outputs': outputs,
        'error': error,
        'startedAt': startedAt?.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'attempts': attempts,
      };

  factory RunNode.fromJson(Map<String, Object?> json) => RunNode(
        id: requiredString(json, 'id'),
        status: RunNodeStatus.values.asNameMap()['${json['status']}'] ??
            RunNodeStatus.pending,
        inputs: requiredStringMap(json, 'inputs'),
        outputs: json['outputs'],
        error: json['error'],
        startedAt: optionalDateTime(json, 'startedAt'),
        finishedAt: optionalDateTime(json, 'finishedAt'),
        attempts: json['attempts'] is int ? json['attempts'] as int : 0,
      );
}
