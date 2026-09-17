/// task 插件的词汇：任务状态机、[Task] 值对象与会话恢复。
///
/// Task Center 是运行时的任务追踪中枢：只回答「现在有哪些任务在跑、各自
/// 什么状态、能不能取消」，不负责调度与执行。状态以 `task/changed` 事件
/// 持久化到 [Session]（append-only，整值替换，按任务 id 折叠最后一个）；
/// 派生状态只折叠会话自身后缀（[Session.ownEvents]），fork 出的会话不继承
/// 父会话的任务树。
library;

import 'dart:convert';

import 'package:conatus_foundation/conatus_foundation.dart';

/// Task 变更事件类型。
const String kTaskEvent = 'task/changed';

/// 恢复时未完成任务的统一失败原因（执行环境已丢失）。
const String kTaskStaleReason = '进程重启，执行环境已丢失';

/// 任务状态。
enum TaskStatus {
  /// 已创建，等待执行。
  pending,

  /// 执行中。
  running,

  /// 暂停。
  paused,

  /// 完成（终态）。
  completed,

  /// 失败（终态）。
  failed,

  /// 取消（终态）。
  cancelled,
}

/// 任务类型。
enum TaskKind {
  /// Agent Loop 的一轮。
  agentTurn,

  /// 子 Agent 委托。
  subAgent,

  /// 后台 shell 进程。
  shell,

  /// 定时提醒交付。
  schedule,

  /// 自定义。
  custom,
}

/// 一个任务。整值替换更新：每次状态变更写一个 `task/changed` 事件。
class Task {
  /// 构造一个任务；[createdAt] 必填，运行/结束时间随状态迁移填入。
  const Task({
    required this.id,
    required this.kind,
    required this.status,
    required this.description,
    required this.createdAt,
    this.startedAt,
    this.finishedAt,
    this.parentTaskId,
    this.metadata = const <String, Object?>{},
    this.result,
    this.error,
  });

  /// copyWith 未传参时的哨兵，区分「不修改」与「置 null」。
  static const Object _unset = Object();

  /// 任务唯一 ID。
  final String id;

  /// 任务类型。
  final TaskKind kind;

  /// 当前状态。
  final TaskStatus status;

  /// 人类可读的描述。
  final String description;

  /// 创建时间。
  final DateTime createdAt;

  /// 开始时间（status 进入 running 时设置）。
  final DateTime? startedAt;

  /// 结束时间（status 进入终态时设置）。
  final DateTime? finishedAt;

  /// 父任务 ID；用于表达任务树（Goal → Agent Turn → Sub-Agent → Shell）。
  final String? parentTaskId;

  /// 元数据；可放 goalId、toolName 等。
  final Map<String, Object?> metadata;

  /// 结果（status == completed 时可选）。
  final Object? result;

  /// 错误（status == failed 时可选）。
  final Object? error;

  /// 是否为终态。
  bool get isTerminal =>
      status == TaskStatus.completed ||
      status == TaskStatus.failed ||
      status == TaskStatus.cancelled;

  /// 是否活跃（可被取消）。
  bool get isActive =>
      status == TaskStatus.pending ||
      status == TaskStatus.running ||
      status == TaskStatus.paused;

  /// 运行时长（未开始则为 null）。
  Duration? get duration {
    final DateTime? start = startedAt;
    if (start == null) return null;
    return (finishedAt ?? DateTime.now()).difference(start);
  }

  /// 返回更新后的副本；可空字段传 null 表示清除。
  Task copyWith({
    TaskStatus? status,
    DateTime? startedAt,
    DateTime? finishedAt,
    Object? result = _unset,
    Object? error = _unset,
  }) {
    return Task(
      id: id,
      kind: kind,
      status: status ?? this.status,
      description: description,
      createdAt: createdAt,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      parentTaskId: parentTaskId,
      metadata: metadata,
      result: identical(result, _unset) ? this.result : result,
      error: identical(error, _unset) ? this.error : error,
    );
  }

  /// 从 JSON 反序列化（恢复时 result / error 为 JSON 形态，非原始对象）。
  factory Task.fromJson(Map<String, Object?> json) => Task(
        id: '${json['id'] ?? ''}',
        kind: TaskKind.values.asNameMap()['${json['kind']}'] ?? TaskKind.custom,
        status: TaskStatus.values.asNameMap()['${json['status']}'] ??
            TaskStatus.pending,
        description: '${json['description'] ?? ''}',
        createdAt: DateTime.parse('${json['createdAt']}'),
        startedAt: _parseDate(json['startedAt']),
        finishedAt: _parseDate(json['finishedAt']),
        parentTaskId: json['parentTaskId'] as String?,
        metadata: <String, Object?>{
          for (final MapEntry<Object?, Object?> entry
              in (json['metadata'] as Map? ?? const <Object?, Object?>{})
                  .entries)
            '${entry.key}': entry.value,
        },
        result: json['result'],
        error: json['error'],
      );

  /// 序列化为 JSON；result / error 保留可编码的 JSON 结构，其余退化为字符串。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'kind': kind.name,
        'status': status.name,
        'description': description,
        'createdAt': createdAt.toIso8601String(),
        'startedAt': startedAt?.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'parentTaskId': parentTaskId,
        'metadata': metadata,
        'result': _encodeJson(result),
        'error': _encodeJson(error),
      };

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    return DateTime.tryParse('$raw');
  }
}

/// 尽量保留 JSON 结构；不可编码的值（如自定义对象）退化为字符串。
Object? _encodeJson(Object? value) {
  try {
    return jsonDecode(jsonEncode(value));
  } catch (_) {
    return '$value';
  }
}

/// Task 相关错误。
class TaskException implements Exception {
  /// 以稳定机器码与可读消息构造。
  const TaskException(this.code, this.message);

  /// 稳定的机器可读错误码（如 `not-found` / `already-terminal`）。
  final String code;

  /// 面向用户/模型的可读消息。
  final String message;

  @override
  String toString() => 'TaskException($code): $message';
}

/// 折叠会话自身后缀里的 `task/changed` 事件，按任务 id 还原任务表
/// （每个 id 只保留最后一个事件，整值替换）。
Map<String, Task> restoreTaskState(Session session) {
  final Map<String, Task> latest = <String, Task>{};
  for (final SessionEvent event in session.ownEvents) {
    if (event.type != kTaskEvent) continue;
    final Object? data = event.data;
    if (data is! Map) continue;
    final Task task = Task.fromJson(Map<String, Object?>.from(data));
    latest[task.id] = task;
  }
  return latest;
}
