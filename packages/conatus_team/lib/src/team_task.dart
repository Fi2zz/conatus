/// 任务板任务的词汇：状态机与 CAS 乐观锁。
///
/// [TeamTask] 是任务板上「做什么」的记录。状态 pending → claimed →
/// done / failed / released（released 回到 pending）。任务有 DAG 依赖
/// （[dependsOn]），只有依赖全 done 才能领取。每次更新用 [version] 做
/// 乐观锁，防止成员之间互相覆盖——调用方传期望版本号，实现层校验通过
/// 后递增。
library;

/// 任务板上的任务状态。
enum TeamTaskStatus {
  /// 待领取。
  pending,

  /// 已领取，执行中。
  claimed,

  /// 完成（终态）。
  done,

  /// 失败（终态）。
  failed,
}

/// 任务板上的一个任务。
class TeamTask {
  const TeamTask({
    required this.id,
    required this.description,
    required this.status,
    required this.dependsOn,
    required this.version,
    required this.createdAt,
    this.assigneeId,
    this.result,
    this.error,
  });

  /// copyWith 未传参时的哨兵，区分「不修改」与「置 null」。
  static const Object _unset = Object();

  /// 任务唯一 ID。
  final String id;

  /// 任务描述。
  final String description;

  /// 当前状态。
  final TeamTaskStatus status;

  /// 分配给谁。null 表示待领取。
  final String? assigneeId;

  /// 依赖哪些任务。全部完成才能领取。
  final List<String> dependsOn;

  /// CAS 版本号。每次更新递增。
  final int version;

  /// 创建时间。
  final DateTime createdAt;

  /// 结果（status == done 时可选）。
  final Object? result;

  /// 错误（status == failed 时可选）。
  final Object? error;

  /// 是否为终态（done / failed）。
  bool get isTerminal =>
      status == TeamTaskStatus.done || status == TeamTaskStatus.failed;

  /// 返回更新后的副本；[assigneeId] / [result] / [error] 传 null 表示清除。
  /// [version] 不传则保留旧值——递增由调用方或实现层负责。
  TeamTask copyWith({
    TeamTaskStatus? status,
    Object? assigneeId = _unset,
    Object? result = _unset,
    Object? error = _unset,
    int? version,
  }) {
    return TeamTask(
      id: id,
      description: description,
      status: status ?? this.status,
      assigneeId: identical(assigneeId, _unset)
          ? this.assigneeId
          : assigneeId as String?,
      dependsOn: dependsOn,
      version: version ?? this.version,
      createdAt: createdAt,
      result: identical(result, _unset) ? this.result : result,
      error: identical(error, _unset) ? this.error : error,
    );
  }

  /// 从 JSON 反序列化。未知状态降级为 pending。
  factory TeamTask.fromJson(Map<String, Object?> json) => TeamTask(
        id: '${json['id'] ?? ''}',
        description: '${json['description'] ?? ''}',
        status: TeamTaskStatus.values.asNameMap()['${json['status']}'] ??
            TeamTaskStatus.pending,
        assigneeId: json['assigneeId'] as String?,
        dependsOn: <String>[
          for (final Object? item
              in (json['dependsOn'] as List<Object?>?) ?? const <Object?>[])
            '$item',
        ],
        version: (json['version'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse('${json['createdAt']}'),
        result: json['result'],
        error: json['error'],
      );

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'description': description,
        'status': status.name,
        'assigneeId': assigneeId,
        'dependsOn': dependsOn,
        'version': version,
        'createdAt': createdAt.toIso8601String(),
        'result': result,
        'error': error,
      };
}
