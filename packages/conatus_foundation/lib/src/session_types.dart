/// session 插件的类型词汇：append-only 日志中的一条事件。
library;

/// 会话日志中的一条事件。
///
/// [seq] 由所属会话在追加时分配（从 0 起单调递增），是事件在日志中的稳定
/// 位置；[type] 是事件类型（如 `'user/message'` / `'tool/result'`）；[data] 是
/// 可 JSON 序列化的负载。
class SessionEvent {
  const SessionEvent({
    required this.seq,
    required this.type,
    required this.time,
    this.data,
  });

  /// 从 JSON 反序列化。
  factory SessionEvent.fromJson(Map<String, Object?> json) => SessionEvent(
        seq: json['seq'] as int? ?? 0,
        type: json['type'] as String? ?? '',
        time:
            DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
        data: json['data'],
      );

  /// 日志内的稳定位置。
  final int seq;

  /// 事件类型。
  final String type;

  /// 事件发生时间。
  final DateTime time;

  /// 可 JSON 序列化的负载。
  final Object? data;

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'seq': seq,
        'type': type,
        'time': time.toIso8601String(),
        if (data != null) 'data': data,
      };

  @override
  String toString() => 'SessionEvent($seq, $type)';
}
