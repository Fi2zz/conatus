/// Session Log 的模型调用记录：把真正发出的请求与收到的响应写进只追加日志。
///
/// 装饰器不改动请求本身，只在两侧记录，因此对既有 Provider 与测试完全透明。
library;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'agent_events.dart';
import 'agent_types.dart';
import 'model_visible_invariant.dart';
import 'session_log_integration.dart';

/// 记录 `llm/request` / `llm/response` 派生事件的 [LlmProvider] 装饰器。
class SessionLogLlmProvider implements LlmProvider {
  /// 包装 [inner]，把每次调用的请求与响应写进 [recorder]。
  SessionLogLlmProvider(this.inner, {required this.recorder});

  /// 被包装的提供方。
  final LlmProvider inner;

  /// 目标记录器。
  final SessionLogRecorder recorder;

  @override
  String get name => inner.name;

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    await _recordRequest(messages, tools);
    await _assertModelVisible();
    final LlmResult result =
        await inner.chat(messages, options: options, tools: tools);
    await recorder.record(
      kLlmResponseEvent,
      data: _responseData(
        content: result.content,
        model: result.model,
        provider: result.provider,
        toolCalls: result.toolCalls,
        usage: result.usage,
      ),
    );
    return result;
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async* {
    await _recordRequest(messages, tools);
    await _assertModelVisible();
    final StringBuffer text = StringBuffer();
    Map<String, dynamic> usage = const <String, dynamic>{};
    String? finishReason;
    List<LlmToolCall> toolCalls = const <LlmToolCall>[];
    await for (final LlmStreamEvent event
        in inner.chatStream(messages, options: options, tools: tools)) {
      if (event is LlmTextDelta) text.write(event.text);
      if (event is LlmStreamDone) {
        usage = event.usage;
        finishReason = event.finishReason;
        toolCalls = event.toolCalls;
      }
      yield event;
    }
    await recorder.record(
      kLlmResponseEvent,
      data: <String, Object?>{
        ..._responseData(
          content: text.toString(),
          model: inner.name,
          provider: inner.name,
          toolCalls: toolCalls,
          usage: usage,
        ),
        'finishReason': finishReason,
      },
    );
  }

  @override
  void close() => inner.close();

  Future<void> _recordRequest(
    List<LlmMessage> messages,
    List<Map<String, dynamic>>? tools,
  ) =>
      recorder.record(kLlmRequestEvent, data: <String, Object?>{
        'provider': inner.name,
        'messages': <Object?>[
          for (final LlmMessage message in messages) message.toJson(),
        ],
        if (tools != null && tools.isNotEmpty) 'tools': tools,
      });

  /// 开发模式断言：发送前确认这条请求能从日志重建（生产默认关闭）。
  ///
  /// 只校验**当前这条请求**对日志的一致性：压缩摘要请求会被识别并跳过，
  /// system prompt 由运行时装配、不在比对范围。
  Future<void> _assertModelVisible() async {
    final String? sessionId = recorder.sessionId;
    if (!recorder.strictModelVisible || sessionId == null) return;
    final List<SessionEvent> events =
        await recorder.log.read(sessionId).toList();
    assertModelVisibleInvariant(events);
  }

  Map<String, Object?> _responseData({
    required String content,
    required String model,
    required String provider,
    required List<LlmToolCall> toolCalls,
    required Map<String, dynamic> usage,
  }) =>
      <String, Object?>{
        'provider': provider,
        'model': model,
        'content': content,
        'toolCalls': toolCallsToJson(toolCalls),
        'usage': usage,
      };
}
