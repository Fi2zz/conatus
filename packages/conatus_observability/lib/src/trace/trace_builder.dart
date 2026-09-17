/// 从 Session Log 派生 span：把只追加日志还原成 trace / span 层级。
///
/// 会话日志是线性因果链（每条事件的 `parentEventId` 指向前一条，见
/// `conatus_agent` 的 `SessionLogRecorder`），树的层级无法从 `parentEventId`
/// 读出，只能按事件类型语义配对。实现见本库的 part `open_span.dart`。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import '../otel/span.dart';

part 'open_span.dart';

/// 根 span 名：一条用户消息到回复的一次完整轮次。
const String kTurnSpanName = 'agent.turn';

/// 子 span 名。
const String kLlmSpanName = 'llm.request';
const String kToolSpanName = 'tool.call';
const String kSubagentSpanName = 'subagent.spawn';

/// 团队派生事件名（`conatus_team` 的 `team_hooks.dart` 未导出常量，此处对齐）。
const String kTeamSpawnedEvent = 'team/spawned';
const String kTeamRemovedEvent = 'team/removed';

/// 从 [SessionLog] 派生 span 的构建器。
///
/// 事件配对规则：`llm/request`×`llm/response`、`tool/call`×`tool/result`
/// （按 `callId`）、`team/spawned`×`team/removed`（按 `teammateId`）。
/// 每条 `user/message` 开一个根 span [kTurnSpanName]，其间的 llm / tool /
/// subagent span 挂为它的子节点。
class TraceBuilder {
  /// 用目标日志构造。
  TraceBuilder({required this.sessionLog});

  /// 派生的数据源。
  final SessionLog sessionLog;

  /// 为一个 Session 构建完整 trace（含全部轮次的根 span，按开始时间排序）。
  Future<List<Span>> buildTrace(String sessionId) async {
    final List<SessionEvent> events =
        await sessionLog.read(sessionId).toList();
    final _SpanBuilder builder = _SpanBuilder();
    for (final SessionEvent event in events) {
      builder.on(event);
    }
    return builder.finish();
  }
}

/// 单次构建的状态机：按事件推进，维护打开的 span。
class _SpanBuilder {
  final List<Span> _done = <Span>[];
  final List<_OpenSpan> _open = <_OpenSpan>[];
  _OpenSpan? _root;
  DateTime? _last;

  /// 事件类型到处理器的分发表（避免单个大 switch 超分支上限）。
  late final Map<String, void Function(SessionEvent)> _handlers =
      <String, void Function(SessionEvent)>{
    kUserMessageEvent: _onUserMessage,
    kLlmRequestEvent: _onLlmRequest,
    kLlmResponseEvent: _onLlmResponse,
    kToolCallEvent: _onToolCall,
    kToolResultEvent: _onToolResult,
    kTeamSpawnedEvent: _onTeamSpawned,
    kTeamRemovedEvent: _onTeamRemoved,
  };

  void on(SessionEvent event) {
    _last = event.time;
    final void Function(SessionEvent)? handler = _handlers[event.type];
    if (handler != null) handler(event);
  }

  /// 收尾：闭合所有未结束的 span，按开始时间排序后返回。
  List<Span> finish() {
    final DateTime end = _last ?? DateTime.now();
    _closeRoot(end);
    for (final _OpenSpan span in _open) {
      _done.add(span.close(end));
    }
    _open.clear();
    _done.sort((Span a, Span b) => a.startTime.compareTo(b.startTime));
    return List<Span>.unmodifiable(_done);
  }

  void _onUserMessage(SessionEvent event) {
    _closeRoot(event.time);
    _root = _OpenSpan.root(event);
  }

  void _onLlmRequest(SessionEvent event) {
    _openChild(_OpenSpan.llm(event));
  }

  void _onLlmResponse(SessionEvent event) {
    final int index = _lastOpenNamed(kLlmSpanName);
    if (index < 0) return;
    final _OpenSpan span = _open.removeAt(index);
    final Map<String, Object?> extra = <String, Object?>{};
    final Object? model = dataOf(event)['model'];
    if (model != null) extra['model'] = model;
    _done.add(
        span.close(event.time, status: SpanStatus.ok, attributes: extra));
  }

  void _onToolCall(SessionEvent event) {
    _openChild(_OpenSpan.tool(event));
  }

  void _onToolResult(SessionEvent event) {
    final int index = _openKeyIndex(toolCallId(event));
    if (index < 0) return;
    final _OpenSpan span = _open.removeAt(index);
    final bool failed = dataOf(event)['isError'] as bool? ?? false;
    _done.add(span.close(event.time,
        status: failed ? SpanStatus.error : SpanStatus.ok));
  }

  void _onTeamSpawned(SessionEvent event) {
    _openChild(_OpenSpan.subagent(event));
  }

  void _onTeamRemoved(SessionEvent event) {
    final int index = _openKeyIndex(teammateId(event));
    if (index < 0) return;
    _done.add(_open.removeAt(index).close(event.time, status: SpanStatus.ok));
  }

  void _openChild(_OpenSpan span) {
    span.traceId = _root?.traceId;
    span.parentSpanId = _root?.spanId;
    _open.add(span);
  }

  void _closeRoot(DateTime end) {
    final _OpenSpan? root = _root;
    if (root == null) return;
    _done.add(root.close(end, status: SpanStatus.ok));
    _root = null;
  }

  /// 从后往前找最后一个仍打开的 [name] span 的下标；没有返回 -1。
  int _lastOpenNamed(String name) {
    for (int i = _open.length - 1; i >= 0; i--) {
      if (_open[i].name == name) return i;
    }
    return -1;
  }

  /// 按配对键（工具 `callId` / 成员 `teammateId`）从后往前找；没有返回 -1。
  int _openKeyIndex(String key) {
    if (key.isEmpty) return -1;
    for (int i = _open.length - 1; i >= 0; i--) {
      if (_open[i].key == key) return i;
    }
    return -1;
  }
}
