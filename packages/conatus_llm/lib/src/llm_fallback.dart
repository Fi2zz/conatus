/// 多提供商回退链。
library;

import 'llm.dart';

/// 回退事件：某个提供商失败、即将切到下一个时回调一次。
///
/// 宿主用它把「主模型不可用，已切到 X」呈给用户——回退是静默发生的，
/// 没有这层提示的话，用户只会看到回答风格突然变了。
typedef LlmFallbackReporter = void Function(LlmFallbackEvent event);

/// 一次回退。
class LlmFallbackEvent {
  const LlmFallbackEvent({
    required this.fromProvider,
    required this.toProvider,
    required this.error,
    required this.remaining,
  });

  /// 失败的提供商名。
  final String fromProvider;

  /// 接下来要试的提供商名。
  final String toProvider;

  /// 引发回退的原始错误。
  final Object error;

  /// 切到 [toProvider] 之后链上还剩几个候选（含它自己）。
  final int remaining;
}

/// 按顺序尝试多个提供商，直到有一个成功。
///
/// 非流式与流式都支持回退：任一提供商失败即尝试下一个，全部失败时抛出
/// 汇总的 [LlmException]（逐个列出每个提供商的错误）。
///
/// 流式回退只在**尚未产出任何事件**时生效；一旦已经 yield 过增量，中途失败
/// 直接向上抛出（已产出的内容无法收回）。
///
/// 重试是**另一个维度**：本类只管「换提供商」，同一提供商内的重试见
/// `RetryingLlm`（`llm_retry.dart`）。典型装配是每个候选各自包一层重试，
/// 再由本类串联。
class FallbackLlm implements LlmProvider {
  FallbackLlm(this.providers, {LlmFallbackReporter? onFallback})
      : _onFallback = onFallback;

  final List<LlmProvider> providers;
  final LlmFallbackReporter? _onFallback;

  @override
  String get name => 'fallback';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    final List<String> errors = <String>[];
    for (int i = 0; i < providers.length; i++) {
      final LlmProvider provider = providers[i];
      try {
        return await provider.chat(messages, options: options, tools: tools);
      } catch (error) {
        errors.add('${provider.name}: ${_describe(error)}');
        _announce(i, provider, error);
      }
    }
    throw LlmException(
      'fallback',
      '所有提供商均失败：\n${errors.join('\n')}',
    );
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async* {
    final List<String> errors = <String>[];
    for (int i = 0; i < providers.length; i++) {
      final LlmProvider provider = providers[i];
      bool emitted = false;
      try {
        await for (final LlmStreamEvent event in provider.chatStream(
          messages,
          options: options,
          tools: tools,
        )) {
          emitted = true;
          yield event;
        }
        return;
      } catch (error) {
        // 已经吐过增量就收不回来了：直接上抛，不换提供商。
        if (emitted) rethrow;
        errors.add('${provider.name}: ${_describe(error)}');
        _announce(i, provider, error);
      }
    }
    throw LlmException(
      'fallback',
      '所有提供商均失败：\n${errors.join('\n')}',
    );
  }

  /// 还有下一个候选时通报一次回退。
  void _announce(int index, LlmProvider failed, Object error) {
    final LlmFallbackReporter? report = _onFallback;
    if (report == null || index + 1 >= providers.length) return;
    report(LlmFallbackEvent(
      fromProvider: failed.name,
      toProvider: providers[index + 1].name,
      error: error,
      remaining: providers.length - index - 1,
    ));
  }

  static String _describe(Object error) =>
      error is LlmException ? error.message : '$error';

  @override
  void close() {
    for (final LlmProvider provider in providers) {
      provider.close();
    }
  }
}
