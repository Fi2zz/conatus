/// session 插件的类型词汇：append-only 日志中的一条事件。
library;

import 'package:conatus_core/conatus_core.dart';

/// 用户消息事件类型。
const String kUserMessageEvent = 'user/message';

/// 助手消息事件类型（可携带工具调用）。
const String kAssistantMessageEvent = 'assistant/message';

/// 工具结果事件类型。
const String kToolResultEvent = 'tool/result';

/// 生成事件唯一 id（进程内单调，跨会话唯一）。
String nextSessionEventId() =>
    'evt-${DateTime.now().microsecondsSinceEpoch}-${_eventSeq++}';

int _eventSeq = 0;

/// 会话日志中的一条事件。
///
/// [seq] 由所属会话在追加时分配（从 0 起单调递增），是事件在日志中的稳定
/// 位置；[type] 是事件类型（如 `'user/message'` / `'tool/result'`）；[data] 是
/// 可 JSON 序列化的负载。
///
/// [id] 是事件唯一标识，用于跨会话引用与 fork（缺省时由
/// [SessionEvent.create] / `Session.append` 生成）；[sessionId] 标明归属会话，
/// 便于 [SessionLog] 这类多会话存储按会话归档；[parentEventId] 表达因果
/// 关系（如工具结果指向触发它的助手消息）。
class SessionEvent {
  const SessionEvent({
    required this.seq,
    required this.type,
    required this.time,
    this.data,
    this.id,
    this.sessionId,
    this.parentEventId,
  });

  /// 构造一条带自动生成 id 的事件。
  factory SessionEvent.create({
    required String sessionId,
    required String type,
    required int seq,
    Object? data,
    String? parentEventId,
    DateTime? time,
    String? id,
  }) =>
      SessionEvent(
        seq: seq,
        type: type,
        time: time ?? DateTime.now(),
        data: data,
        id: id ?? nextSessionEventId(),
        sessionId: sessionId,
        parentEventId: parentEventId,
      );

  /// 从 JSON 反序列化。
  factory SessionEvent.fromJson(Map<String, Object?> json) => SessionEvent(
        seq: json['seq'] as int? ?? 0,
        type: json['type'] as String? ?? '',
        time:
            DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
        data: json['data'],
        id: json['id'] as String?,
        sessionId: json['sessionId'] as String?,
        parentEventId: json['parentEventId'] as String?,
      );

  /// 日志内的稳定位置。
  final int seq;

  /// 事件类型。
  final String type;

  /// 事件发生时间。
  final DateTime time;

  /// 可 JSON 序列化的负载。
  final Object? data;

  /// 事件唯一标识；旧数据可能为 `null`。
  final String? id;

  /// 归属会话 id；由 `Session.append` / [SessionLog] 写入时补齐。
  final String? sessionId;

  /// 触发本事件的父事件 id，用于因果追踪。
  final String? parentEventId;

  /// 复制并替换若干字段。
  SessionEvent copyWith({
    int? seq,
    String? type,
    DateTime? time,
    Object? data,
    String? id,
    String? sessionId,
    String? parentEventId,
  }) =>
      SessionEvent(
        seq: seq ?? this.seq,
        type: type ?? this.type,
        time: time ?? this.time,
        data: data ?? this.data,
        id: id ?? this.id,
        sessionId: sessionId ?? this.sessionId,
        parentEventId: parentEventId ?? this.parentEventId,
      );

  /// 序列化为 JSON；负载中的凭据字段会被自动脱敏。
  Map<String, Object?> toJson() => <String, Object?>{
        'seq': seq,
        'type': type,
        'time': time.toIso8601String(),
        if (data != null) 'data': redactSecrets(data),
        if (id != null) 'id': id,
        if (sessionId != null) 'sessionId': sessionId,
        if (parentEventId != null) 'parentEventId': parentEventId,
      };

  @override
  String toString() => 'SessionEvent($seq, $type)';
}
