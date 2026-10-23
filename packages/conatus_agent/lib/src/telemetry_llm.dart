/// 模型调用的遥测装饰器：`llm.request` / `llm.failed`。
library;

import 'package:conatus_llm/conatus_llm.dart';
import 'cost.dart';
import 'telemetry.dart';

/// 给任意 [LlmProvider] 加 `llm.request` / `llm.failed` 埋点的装饰器。
///
/// 注入 [rate] 时事件额外带 `cost`；无论是否注入，只要拿到用量就带归一后的
/// `promptTokens` / `cachedTokens` / `completionTokens`。
class TelemetryLlmProvider implements LlmProvider {
  TelemetryLlmProvider(this.inner, {required this.telemetry, this.rate});

  /// 被包装的 provider。
  final LlmProvider inner;

  /// 遥测导出器。
  final Telemetry telemetry;

  /// 成本费率；null 表示未知（不写 `cost`）。
  final ModelRate? rate;

  @override
  String get name => inner.name;

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    final Stopwatch watch = Stopwatch()..start();
    try {
      final LlmResult result =
          await inner.chat(messages, options: options, tools: tools);
      final TokenUsage usage = TokenUsage.parse(result.usage);
      telemetry.emit(TelemetryEvent('llm.request', data: <String, Object?>{
        'provider': inner.name,
        'model': result.model,
        'ms': watch.elapsedMilliseconds,
        'messages': messages.length,
        'tools': tools?.length ?? 0,
        'toolCalls': result.toolCalls.length,
        if (usage.known) 'promptTokens': usage.prompt,
        if (usage.known) 'cachedTokens': usage.cachedPrompt,
        if (usage.known) 'completionTokens': usage.completion,
        if (usage.known && rate != null) 'cost': rate!.costOf(usage),
      }));
      return result;
    } catch (error) {
      telemetry.emit(TelemetryEvent('llm.failed', data: <String, Object?>{
        'provider': inner.name,
        'ms': watch.elapsedMilliseconds,
        'error': '$error',
      }));
      rethrow;
    }
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      inner.chatStream(messages, options: options, tools: tools);

  @override
  void close() => inner.close();
}
