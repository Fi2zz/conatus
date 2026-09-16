/// schedule 插件的数据模型：持久记录、模型可见视图与折叠结果。
///
/// 提醒状态的唯一权威是会话事件流里名为 [kScheduleChangeEvent] 的事件；本文件只
/// 描述值与序列化形状，严格解码与折叠见 `schedule_decode.dart`。
library;

import 'schedule_time.dart';

/// 持久提醒变更事件的类型名。
const String kScheduleChangeEvent = 'schedule/change';

/// 本包实现的持久协议版本。
const int kScheduleChangeVersion = 1;

/// 固定间隔提醒的最小间隔（秒）。
const int kMinEveryIntervalSeconds = 300;

/// 交付边界常量：提醒只在原会话内交付。
const String kScheduleDeliveryMode = 'session-local';

/// 提醒规则种类。
enum ScheduleKind {
  /// 延迟指定秒数后触发的一次性提醒。
  after('after'),

  /// 指定绝对时刻的一次性提醒。
  at('at'),

  /// 按固定间隔重复的提醒。
  every('every');

  const ScheduleKind(this.wire);

  /// 持久 JSON 中的判别值。
  final String wire;
}

/// 提醒相对当前墙钟的交付时机。
enum ScheduleState {
  /// 目标时刻仍在未来。
  scheduled('scheduled'),

  /// 目标时刻已到、等待交付。
  overdue('overdue');

  const ScheduleState(this.wire);

  /// 工具结果中的判别值。
  final String wire;
}

/// 一条持久提醒记录。
class ScheduleRecord {
  /// 构造一条记录。
  ScheduleRecord({
    required this.id,
    required this.kind,
    required this.prompt,
    required this.scheduledAt,
    this.afterSeconds,
    this.everySeconds,
  });

  /// 会话内唯一、永不复用的标识。
  final String id;

  /// 规则种类，决定 [afterSeconds] / [everySeconds] 哪一个有值。
  final ScheduleKind kind;

  /// 创建时提供的提醒内容（已去首尾空白）。
  final String prompt;

  /// 四位年份 RFC 3339 UTC 目标时刻。
  ///
  /// [ScheduleKind.every] 下它表示「最早尚未派发的、与创建锚点对齐的发生时点」。
  final DateTime scheduledAt;

  /// 创建时接受的延迟秒数，仅 [ScheduleKind.after] 有值。
  final int? afterSeconds;

  /// 创建时接受的固定间隔秒数，仅 [ScheduleKind.every] 有值。
  final int? everySeconds;

  /// 序列化为持久 JSON；键顺序与协议一致。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'kind': kind.wire,
        'prompt': prompt,
        if (afterSeconds != null) 'afterSeconds': afterSeconds,
        if (everySeconds != null) 'everySeconds': everySeconds,
        'scheduledAt': formatUtcInstant(scheduledAt),
      };

  /// 派生同一记录的副本，仅改目标时刻（固定间隔派发后推进用）。
  ScheduleRecord withScheduledAt(DateTime next) => ScheduleRecord(
        id: id,
        kind: kind,
        prompt: prompt,
        scheduledAt: next,
        afterSeconds: afterSeconds,
        everySeconds: everySeconds,
      );
}

/// 一条活动提醒的模型可见视图。
class ScheduleView {
  /// 构造一条视图。
  const ScheduleView({required this.record, required this.state});

  /// 被呈现的持久记录。
  final ScheduleRecord record;

  /// 相对当前墙钟的时机状态。
  final ScheduleState state;

  /// 序列化为工具结果；记录字段在前，状态与交付模式在后。
  Map<String, Object?> toJson() => <String, Object?>{
        ...record.toJson(),
        'state': state.wire,
        'deliveryMode': kScheduleDeliveryMode,
      };
}

/// 一条已到期的固定间隔提醒，以及被选中的最新发生时点。
class ScheduleDue {
  /// 构造一条到期项。
  const ScheduleDue({required this.record, required this.occurrenceAt});

  /// 仍然活动的固定间隔记录。
  final ScheduleRecord record;

  /// 该记录在决策时点最新一个锚点对齐的到期时点。
  final DateTime occurrenceAt;
}

/// 一次回放的结果：活动记录按创建顺序，[seenIds] 保留所有用过的标识。
class ScheduleFold {
  /// 构造一次折叠结果。
  ScheduleFold({
    required List<ScheduleRecord> active,
    required List<String> seenIds,
  })  : active = List<ScheduleRecord>.unmodifiable(active),
        seenIds = List<String>.unmodifiable(seenIds);

  /// 仍然活动的记录，保持创建顺序。
  final List<ScheduleRecord> active;

  /// 本会话后缀里出现过的全部 id（含已删除、已派发的）。
  final List<String> seenIds;

  /// 按 id 找一条活动记录；不存在返回 `null`。
  ScheduleRecord? find(String id) {
    for (final ScheduleRecord record in active) {
      if (record.id == id) return record;
    }
    return null;
  }
}

/// `schedule_delete` 的结果：删除成功，或目标不存在（不改动任何状态）。
class ScheduleDeleteResult {
  /// 构造一个删除结果。
  const ScheduleDeleteResult({required this.id, required this.deleted});

  /// 被请求删除的标识。
  final String id;

  /// 是否确实删掉了一条活动记录。
  final bool deleted;

  /// 序列化为工具结果。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'deleted': deleted,
        if (!deleted) 'code': 'schedule_not_found',
      };
}
