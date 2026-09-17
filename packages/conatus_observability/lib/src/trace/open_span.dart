/// trace_builder 的内部支撑：已打开、尚未闭合的 span。
///
/// 本文件是 `trace_builder.dart` 的 part，共享其库的私有可见性，不作为公共
/// API 导出。
part of 'trace_builder.dart';

/// 一个已打开、尚未闭合的 span；闭合时才定稿为不可变的 [Span]。
class _OpenSpan {
  _OpenSpan({
    required this.spanId,
    required this.name,
    required this.start,
    required this.attributes,
    this.key,
    this.traceId,
  });

  /// 由一条 [SessionEvent] 构造根 span（一条用户消息）。
  factory _OpenSpan.root(SessionEvent event) => _OpenSpan(
        spanId: event.id ?? event.type,
        name: kTurnSpanName,
        start: event.time,
        attributes: dataOf(event),
        traceId: event.id ?? event.type,
      );

  /// 由 `llm/request` 构造。
  factory _OpenSpan.llm(SessionEvent event) => _OpenSpan(
        spanId: event.id ?? event.type,
        name: kLlmSpanName,
        start: event.time,
        attributes: dataOf(event),
      );

  /// 由 `tool/call` 构造；[key] 为 `callId`，供 `tool/result` 配对。
  factory _OpenSpan.tool(SessionEvent event) => _OpenSpan(
        spanId: event.id ?? event.type,
        name: kToolSpanName,
        start: event.time,
        attributes: dataOf(event),
        key: toolCallId(event),
      );

  /// 由 `team/spawned` 构造；[key] 为 `teammateId`，供 `team/removed` 配对。
  factory _OpenSpan.subagent(SessionEvent event) => _OpenSpan(
        spanId: event.id ?? event.type,
        name: kSubagentSpanName,
        start: event.time,
        attributes: dataOf(event),
        key: teammateId(event),
      );

  /// 标识（派生自事件 id）。
  final String spanId;

  /// span 名。
  final String name;

  /// 开始时间。
  final DateTime start;

  /// 起始属性。
  final Map<String, Object?> attributes;

  /// 配对键（工具 `callId` / 成员 `teammateId`）；根 span 为 `null`。
  final String? key;

  /// 所属 trace 标识；根 span 在构造时自指，子 span 由状态机补齐。
  String? traceId;

  /// 父 span 标识；根 span 保持 `null`。
  String? parentSpanId;

  /// 以 [end] 为终点定稿；负时长钳为 0，[attributes] 合并进起始属性。
  Span close(
    DateTime end, {
    SpanStatus status = SpanStatus.unset,
    Map<String, Object?>? attributes,
  }) {
    final Duration raw = end.difference(start);
    return Span(
      traceId: traceId ?? '',
      spanId: spanId,
      parentSpanId: parentSpanId,
      name: name,
      startTime: start,
      duration: raw.isNegative ? Duration.zero : raw,
      attributes: attributes == null
          ? this.attributes
          : <String, Object?>{...this.attributes, ...attributes},
      status: status,
    );
  }
}

/// 取事件负载；非 Map 时回退为空表。
Map<String, Object?> dataOf(SessionEvent event) {
  final Object? data = event.data;
  if (data is Map) return data.cast<String, Object?>();
  return const <String, Object?>{};
}

/// 工具事件的 `callId`。
String toolCallId(SessionEvent event) =>
    dataOf(event)['callId'] as String? ?? '';

/// 团队事件的 `teammateId`。
String teammateId(SessionEvent event) =>
    dataOf(event)['teammateId'] as String? ?? '';
