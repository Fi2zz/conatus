/// 团队成员的词汇：角色与状态机入口。
///
/// [Teammate] 是任务板上「谁在做」的记录：状态机 idle → working → done /
/// failed（见 [TeammateStatus]）。成员的生命周期绑定队长——队长释放时，
/// 所有成员自动终止。成员不共享消息历史，只通过任务板与直达消息交换
/// 结论，不交换过程。
library;

/// 团队角色。
enum TeamRole {
  /// 队长，可创建成员、分配任务。
  lead,

  /// 成员，只能领取任务、汇报结果。
  member,
}

/// 成员状态。
enum TeammateStatus {
  /// 空闲，等待任务。
  idle,

  /// 工作中。
  working,

  /// 等待中（等待依赖任务完成）。
  waiting,

  /// 完成（终态）。
  done,

  /// 失败（终态）。
  failed,
}

/// 一个团队成员。
class Teammate {
  const Teammate({
    required this.id,
    required this.name,
    required this.role,
    required this.status,
    required this.tools,
    required this.createdAt,
    this.systemPrompt,
    this.currentTaskId,
  });

  /// copyWith 未传参时的哨兵，区分「不修改」与「置 null」。
  static const Object _unset = Object();

  /// 成员唯一 ID。
  final String id;

  /// 成员名字，如 "security-reviewer"。
  final String name;

  /// 角色。
  final TeamRole role;

  /// 当前状态。
  final TeammateStatus status;

  /// 该成员可用的工具白名单。
  final List<String> tools;

  /// 该成员的角色定义（system prompt）。
  final String? systemPrompt;

  /// 当前正在处理的任务 ID。
  final String? currentTaskId;

  /// 创建时间。
  final DateTime createdAt;

  /// 是否为终态（done / failed）。
  bool get isTerminal =>
      status == TeammateStatus.done || status == TeammateStatus.failed;

  /// 返回更新后的副本；[currentTaskId] 传 null 表示清除。
  Teammate copyWith({
    TeammateStatus? status,
    Object? currentTaskId = _unset,
  }) {
    return Teammate(
      id: id,
      name: name,
      role: role,
      status: status ?? this.status,
      tools: tools,
      createdAt: createdAt,
      systemPrompt: systemPrompt,
      currentTaskId: identical(currentTaskId, _unset)
          ? this.currentTaskId
          : currentTaskId as String?,
    );
  }

  /// 从 JSON 反序列化。未知枚举降级为默认值。
  factory Teammate.fromJson(Map<String, Object?> json) => Teammate(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        role: TeamRole.values.asNameMap()['${json['role']}'] ??
            TeamRole.member,
        status: TeammateStatus.values.asNameMap()['${json['status']}'] ??
            TeammateStatus.idle,
        tools: <String>[
          for (final Object? item
              in (json['tools'] as List<Object?>?) ?? const <Object?>[])
            '$item',
        ],
        createdAt: DateTime.parse('${json['createdAt']}'),
        systemPrompt: json['systemPrompt'] as String?,
        currentTaskId: json['currentTaskId'] as String?,
      );

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'role': role.name,
        'status': status.name,
        'tools': tools,
        'createdAt': createdAt.toIso8601String(),
        'systemPrompt': systemPrompt,
        'currentTaskId': currentTaskId,
      };
}
