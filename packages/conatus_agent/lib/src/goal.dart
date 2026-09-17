/// goal 插件：长期目标的词汇。
///
/// Goal 与 Plan Mode 解决两个时间尺度的问题：Plan Mode 管「这一次怎么做」，
/// Goal 管「长期要做什么」。状态以 `goal/changed` 事件持久化到 [Session]
/// （append-only，整值替换，折叠最后一条）；派生状态只折叠会话自身后缀
/// （[Session.ownEvents]），fork 出的会话不继承目标。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

/// Goal 变更事件类型。
const String kGoalEvent = 'goal/changed';

/// 达到轮次上限时的阻塞原因（续行驱动器与默认服务共用）。
const String kGoalRoundLimitReason = '达到轮次上限，等待用户介入';

/// 目标状态。
enum GoalStatus {
  /// 活动，可被续行驱动器推进。
  active,

  /// 暂停，需用户显式 resume。
  paused,

  /// 阻塞，需用户介入。
  blocked,

  /// 完成，终态。
  completed,

  /// 清除，终态。
  cleared,
}

/// 目标修订记录。
class GoalRevision {
  const GoalRevision({required this.text, required this.revisedAt});

  /// 该版文本。
  final String text;

  /// 修订时间。
  final DateTime revisedAt;

  /// 从 JSON 反序列化。
  factory GoalRevision.fromJson(Map<String, Object?> json) => GoalRevision(
        text: '${json['text'] ?? ''}',
        revisedAt: DateTime.parse('${json['revisedAt']}'),
      );

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'text': text,
        'revisedAt': revisedAt.toIso8601String(),
      };
}

/// 一个长期目标。每会话至多一个当前目标。
class Goal {
  const Goal({
    required this.id,
    required this.text,
    required this.status,
    required this.round,
    required this.maxRounds,
    required this.createdAt,
    required this.updatedAt,
    this.revisions = const <GoalRevision>[],
    this.blockReason,
  });

  /// copyWith 未传参时的哨兵，区分「不修改」与「置 null」。
  static const Object _unset = Object();

  /// 目标唯一 ID。
  final String id;

  /// 目标描述。
  final String text;

  /// 当前状态。
  final GoalStatus status;

  /// 已用轮次。
  final int round;

  /// 轮次上限。
  final int maxRounds;

  /// 创建时间。
  final DateTime createdAt;

  /// 最后更新时间。
  final DateTime updatedAt;

  /// 修订历史（含初版）。
  final List<GoalRevision> revisions;

  /// 阻塞原因（status == blocked 时非空）。
  final String? blockReason;

  /// 是否为终态。
  bool get isTerminal =>
      status == GoalStatus.completed || status == GoalStatus.cleared;

  /// 是否可被续行驱动器推进。
  bool get isAdvanceable => status == GoalStatus.active;

  /// 返回更新后的副本；[blockReason] 传 null 表示清除。
  Goal copyWith({
    String? text,
    GoalStatus? status,
    int? round,
    DateTime? updatedAt,
    List<GoalRevision>? revisions,
    Object? blockReason = _unset,
  }) {
    return Goal(
      id: id,
      text: text ?? this.text,
      status: status ?? this.status,
      round: round ?? this.round,
      maxRounds: maxRounds,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      revisions: revisions ?? this.revisions,
      blockReason: identical(blockReason, _unset)
          ? this.blockReason
          : blockReason as String?,
    );
  }

  /// 从 JSON 反序列化。
  factory Goal.fromJson(Map<String, Object?> json) => Goal(
        id: '${json['id'] ?? ''}',
        text: '${json['text'] ?? ''}',
        status: GoalStatus.values.asNameMap()['${json['status']}'] ??
            GoalStatus.active,
        round: (json['round'] as num?)?.toInt() ?? 0,
        maxRounds: (json['maxRounds'] as num?)?.toInt() ?? 256,
        createdAt: DateTime.parse('${json['createdAt']}'),
        updatedAt: DateTime.parse('${json['updatedAt']}'),
        revisions: <GoalRevision>[
          for (final Object? item
              in (json['revisions'] as List<Object?>?) ?? const <Object?>[])
            if (item is Map)
              GoalRevision.fromJson(Map<String, Object?>.from(item)),
        ],
        blockReason: json['blockReason'] as String?,
      );

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'text': text,
        'status': status.name,
        'round': round,
        'maxRounds': maxRounds,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'revisions': <Map<String, Object?>>[
          for (final GoalRevision r in revisions) r.toJson(),
        ],
        'blockReason': blockReason,
      };
}

/// Goal 相关错误。
class GoalException implements Exception {
  const GoalException(this.code, this.message);

  /// 稳定的机器可读错误码（如 `already_exists` / `invalid_status`）。
  final String code;

  /// 面向用户/模型的可读消息。
  final String message;

  @override
  String toString() => 'GoalException($code): $message';
}

/// 折叠会话自身后缀里最后一个 `goal/changed` 事件，还原目标状态；
/// 无事件或最后状态为 `cleared` 时返回 `null`。
Goal? restoreGoalState(Session session) {
  for (final SessionEvent event in session.ownEvents.reversed) {
    if (event.type != kGoalEvent) continue;
    final Object? data = event.data;
    if (data is Map && data['status'] != 'cleared') {
      return Goal.fromJson(Map<String, Object?>.from(data));
    }
    return null;
  }
  return null;
}
