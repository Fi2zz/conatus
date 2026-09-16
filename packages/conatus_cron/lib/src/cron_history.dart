/// cron 运行记录：历史 JSONL 的一行（值对象 + 宽容解码）。
///
/// 日期一律 ISO 串（兼容读取 dsh-cron 的毫秒数）；解码缺 id 或形状不符返回
/// null，由调用方跳过错行。账本（加载、追加、封顶与状态推进）见 `cron_book.dart`。
library;

import 'cron_types.dart';

/// 一条运行记录（历史 JSONL 的一行）。
class CronRunRecord {
  /// 构造一条记录。
  CronRunRecord({
    required this.id,
    required this.seq,
    required this.taskId,
    required this.prompt,
    required this.sessionId,
    required this.scheduledFor,
    required this.firedAt,
    required this.status,
    this.excerpt,
    this.endReason,
    this.startedAt,
    this.completedAt,
  });

  /// 记录 id：`run-<seq>-<base36 毫秒>`。
  final String id;

  /// 单调递增的序号。
  final int seq;

  /// 任务 id。
  final String taskId;

  /// 任务内容快照。
  final String prompt;

  /// 交付目标会话 id（绑定会话；无绑定时为 null）。
  final String? sessionId;

  /// 排期的触发时刻。
  final DateTime scheduledFor;

  /// 实际交付时刻。
  final DateTime firedAt;

  /// 记录状态（[CronRunStatus]）。
  String status;

  /// 执行结果摘要（截断到 [kCronExcerptLength]）。
  String? excerpt;

  /// 结束原因（dsh-cron 事件流语义保留）。
  final String? endReason;

  /// 开始执行时刻。
  final DateTime? startedAt;

  /// 执行结束时刻。
  DateTime? completedAt;

  /// 序列化为历史 JSONL 的一行；创建时必有的字段始终写出，其余 null 省略。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'seq': seq,
        'taskId': taskId,
        'prompt': prompt,
        'sessionId': sessionId,
        'scheduledFor': formatCronInstant(scheduledFor),
        'firedAt': formatCronInstant(firedAt),
        'status': status,
        if (excerpt != null) 'excerpt': excerpt,
        if (endReason != null) 'endReason': endReason,
        if (startedAt != null) 'startedAt': formatCronInstant(startedAt),
        if (completedAt != null) 'completedAt': formatCronInstant(completedAt),
      };

  /// 从一行 JSON 宽容解码；缺 id 或形状不符返回 null（调用方跳过错行）。
  static CronRunRecord? fromJson(Map<String, Object?> json) {
    final Object? id = json['id'];
    if (id is! String || id.isEmpty) return null;
    return CronRunRecord(
      id: id,
      seq: decodeCronInt(json['seq']) ?? 0,
      taskId: json['taskId'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      sessionId: json['sessionId'] as String?,
      scheduledFor: decodeCronInstant(json['scheduledFor']) ?? _epoch,
      firedAt: decodeCronInstant(json['firedAt']) ?? _epoch,
      status: json['status'] as String? ?? CronRunStatus.delivered,
      excerpt: json['excerpt'] as String?,
      endReason: json['endReason'] as String?,
      startedAt: decodeCronInstant(json['startedAt']),
      completedAt: decodeCronInstant(json['completedAt']),
    );
  }
}

/// 交付前预分配的记录标识（seq 随之占用；交付被拒时由账本归还）。
class CronRecordRef {
  /// 构造一个记录标识。
  const CronRecordRef({required this.id, required this.seq});

  /// 记录 id（交付端以此关联后续 finishRun）。
  final String id;

  /// 序号。
  final int seq;
}

final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

/// 宽容解码整数：int 直取，整数值的 num 转换，其余返回 null。
int? decodeCronInt(Object? value) {
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  return null;
}

/// 宽容解码瞬时：ISO 串或毫秒数（dsh-cron 兼容），其余返回 null。
DateTime? decodeCronInstant(Object? value) {
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  return null;
}
