/// span 语义：分布式追踪的最小模型，由 [TraceBuilder] 从 Session Log 派生。
library;

/// 一个 span 的结局状态。
enum SpanStatus {
  /// 未收到结束事件（如 `llm/request` 没有对应的 `llm/response`）。
  unset,

  /// 正常结束。
  ok,

  /// 出错（如工具调用返回 isError）。
  error,
}

/// 一个 span：一条带时间跨度的追踪片段。
///
/// 不可变；[TraceBuilder] 在配对到结束事件时才构造完整实例。
class Span {
  const Span({
    required this.traceId,
    required this.spanId,
    required this.name,
    required this.startTime,
    required this.duration,
    this.parentSpanId,
    this.attributes = const <String, Object?>{},
    this.status = SpanStatus.unset,
  });

  /// 所属 trace 的标识（根 span 的 id）。
  final String traceId;

  /// 本 span 的标识（派生自事件 id）。
  final String spanId;

  /// 父 span 标识；根 span 为 `null`。
  final String? parentSpanId;

  /// span 名（`agent.turn` / `llm.request` / `tool.call` / `subagent.spawn`）。
  final String name;

  /// 开始时间。
  final DateTime startTime;

  /// 持续时长。
  final Duration duration;

  /// 附加属性。
  final Map<String, Object?> attributes;

  /// 结局状态。
  final SpanStatus status;
}
