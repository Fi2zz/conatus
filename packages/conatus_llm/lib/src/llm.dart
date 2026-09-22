/// llm 插件：统一的大模型接入层。
///
/// 支持 OpenAI 兼容的两种请求形态（[LlmApiStyle]）：
///
/// * [LlmApiStyle.chat]：`{baseUrl}/chat/completions`，消息用 `messages`；
/// * [LlmApiStyle.responses]：`{baseUrl}/responses`，消息用 `input`。
///
/// 默认提供商顺序为 **豆包 → DeepSeek**，任一成功即返回。
/// 非流式走 [LlmProvider.chat]，流式走 [LlmProvider.chatStream]。
/// 具体 provider 实现见 `llm_openai.dart`。
library;

import 'package:conatus_core/conatus_core.dart';

/// OpenAI 兼容端点的请求形态。
enum LlmApiStyle { chat, responses }

/// 模型请求的一次工具调用。
class LlmToolCall {
  const LlmToolCall({
    required this.id,
    required this.name,
    this.arguments = '{}',
  });

  /// 调用标识（与 tool 结果消息的 [LlmMessage.toolCallId] 配对）。
  final String id;

  /// 工具名。
  final String name;

  /// 原始 JSON 参数串（未解析）。
  final String arguments;

  /// 编译为 Chat Completions 的 tool_call 项。
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': 'function',
        'function': <String, dynamic>{'name': name, 'arguments': arguments},
      };

  @override
  String toString() => 'LlmToolCall($name, $arguments)';
}

/// 聊天消息携带的图片（多模态输入）。
class LlmImage {
  const LlmImage({required this.mimeType, required this.base64Data});

  /// 图片 MIME 类型，如 `image/png`。
  final String mimeType;

  /// 图片字节的 base64 编码（不含 data URL 前缀）。
  final String base64Data;

  /// data URL 形式，供 Chat Completions 的 `image_url` 与 Responses 的
  /// `input_image` 共用。
  String get dataUrl => 'data:$mimeType;base64,$base64Data';
}

/// 聊天消息。
///
/// * 普通消息：`LlmMessage('user', '你好')`；
/// * 携带图片：`LlmMessage('user', '看这张图', images: [LlmImage(...)])`；
/// * 助手工具调用：`LlmMessage('assistant', '', toolCalls: [...])`；
/// * 工具结果：`LlmMessage('tool', '结果', toolCallId: 'call_1')`。
class LlmMessage {
  const LlmMessage(
    this.role,
    this.content, {
    this.toolCalls = const <LlmToolCall>[],
    this.toolCallId,
    this.cacheable = false,
    this.images = const <LlmImage>[],
  });

  final String role; // system / user / assistant / tool
  final String content;

  /// 助手消息请求的工具调用。
  final List<LlmToolCall> toolCalls;

  /// 工具结果消息对应的调用 id（role 为 `tool` 时必填）。
  final String? toolCallId;

  /// 是否属于可缓存的稳定前缀（如 system prompt + 工具定义）。
  ///
  /// 纯本地标记，**不会**写入请求体：豆包 / DeepSeek 的前缀缓存由服务端自动
  /// 生效，塞入非标字段可能被拒。它只用于 `CachingLlmProvider` 计算连续可缓存
  /// 前缀与缓存度量。
  final bool cacheable;

  /// 消息携带的图片；为空时消息退化为纯文本。
  final List<LlmImage> images;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'role': role,
        'content': images.isEmpty
            ? content
            : <Map<String, dynamic>>[
                <String, dynamic>{'type': 'text', 'text': content},
                for (final LlmImage image in images)
                  <String, dynamic>{
                    'type': 'image_url',
                    'image_url': <String, String>{'url': image.dataUrl},
                  },
              ],
        if (toolCallId != null) 'tool_call_id': toolCallId,
        if (toolCalls.isNotEmpty)
          'tool_calls': <Map<String, dynamic>>[
            for (final LlmToolCall call in toolCalls) call.toJson(),
          ],
      };
}

/// 聊天补全结果。
class LlmResult {
  const LlmResult({
    required this.content,
    required this.provider,
    required this.model,
    this.usage = const <String, dynamic>{},
    this.toolCalls = const <LlmToolCall>[],
  });

  final String content;
  final String provider;
  final String model;
  final Map<String, dynamic> usage;

  /// 模型请求的工具调用；无工具调用时为空。
  final List<LlmToolCall> toolCalls;

  @override
  String toString() => '[$provider/$model] $content';
}

/// 流式事件。
sealed class LlmStreamEvent {
  const LlmStreamEvent();
}

/// 正文增量。
final class LlmTextDelta extends LlmStreamEvent {
  const LlmTextDelta(this.text);

  final String text;

  @override
  String toString() => 'LlmTextDelta($text)';
}

/// 思考增量（如豆包 `reasoning_content` / Responses 的 reasoning 事件）。
final class LlmReasoningDelta extends LlmStreamEvent {
  const LlmReasoningDelta(this.text);

  final String text;

  @override
  String toString() => 'LlmReasoningDelta($text)';
}

/// 流结束：携带累计用量、结束原因与工具调用。
///
/// 由 `chatStream` 在流末尾产出一次；若流中途失败则不产出。
final class LlmStreamDone extends LlmStreamEvent {
  const LlmStreamDone({
    this.usage = const <String, dynamic>{},
    this.finishReason,
    this.toolCalls = const <LlmToolCall>[],
  });

  final Map<String, dynamic> usage;
  final String? finishReason;

  /// 流式累积完成的工具调用；无工具调用时为空。
  ///
  /// 工具参数以 JSON 分片到达，须攒到流结束才能得到完整调用，故在终态一次性给出。
  final List<LlmToolCall> toolCalls;

  @override
  String toString() =>
      'LlmStreamDone($finishReason, ${toolCalls.length} toolCalls, $usage)';
}

/// 大模型提供商抽象。
abstract class LlmProvider {
  String get name;

  /// 发送非流式聊天补全请求。
  ///
  /// [tools] 是工具 schema 列表（`{name, description, parameters}`），非空时
  /// 以原生 function calling 下发；结果里的工具调用见 [LlmResult.toolCalls]。
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  });

  /// 发送流式聊天补全请求。
  ///
  /// [tools] 语义与 [chat] 一致；工具调用以 JSON 分片到达，攒到流结束后
  /// 由终态 [LlmStreamDone.toolCalls] 一次性给出。
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  });

  /// 释放底层资源（如 HTTP 客户端）。默认无操作。
  void close() {}
}

/// 提供商调用失败时抛出。
class LlmException implements Exception {
  const LlmException(this.provider, this.message, [this.statusCode]);

  final String provider;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'LlmException($provider, $statusCode): $message';
}

/// 按顺序尝试多个提供商，直到有一个成功。
///
/// 默认顺序：豆包 → DeepSeek。
/// 非流式与流式都支持回退：任一提供商失败即尝试下一个，
/// 全部失败时抛出 [LlmException]，消息中汇总所有提供商的错误。
///
/// 流式回退只在**尚未产出任何事件**时生效；一旦已经 yield 过增量，
/// 中途失败会直接向上抛出（已产出的内容无法收回）。
class FallbackLlm implements LlmProvider {
  FallbackLlm(this.providers);

  final List<LlmProvider> providers;

  @override
  String get name => 'fallback';


  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    final List<String> errors = <String>[];
    for (final LlmProvider provider in providers) {
      try {
        return await provider.chat(messages, options: options, tools: tools);
      } on LlmException catch (e) {
        errors.add('${provider.name}: ${e.message}');
      } catch (e) {
        errors.add('${provider.name}: $e');
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
    for (final LlmProvider provider in providers) {
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
      } on LlmException catch (e) {
        if (emitted) rethrow;
        errors.add('${provider.name}: ${e.message}');
      } catch (e) {
        if (emitted) rethrow;
        errors.add('${provider.name}: $e');
      }
    }
    throw LlmException(
      'fallback',
      '所有提供商均失败：\n${errors.join('\n')}',
    );
  }

  @override
  void close() {
    for (final LlmProvider provider in providers) {
      provider.close();
    }
  }
}

/// 将 LLM 服务提供到上下文中。
///
/// ```dart
/// app.plugin('llm', (ctx) => provideLlm(ctx));
///
/// app.plugin('chat', (ctx) {
///   ctx.inject(['llm'], (child) async {
///     final llm = child.require<FallbackLlm>('llm');
///     final result = await llm.chat([
///       LlmMessage('user', '你好'),
///     ]);
///     print(result);
///   });
/// });
/// ```
Disposer provideLlm(Context ctx, {required FallbackLlm llm}) {
  // 具体提供商（豆包 / DeepSeek）与回退链的装配在调用方：conatus_code 的
  // `lib/providers.dart` 提供 `DoubaoProvider` / `DeepSeekProvider`。
  final FallbackLlm instance = llm;
  final Disposer disposer = ctx.provide('llm', instance);
  ctx.onDispose(instance.close);
  return disposer;
}
