/// 非 Agent 场景入口：直接压缩一组消息。
library;

import 'package:conatus_llm/conatus_llm.dart';

import 'ccr_memory_store.dart';
import 'ccr_store.dart';
import 'content_compressor.dart';
import 'context_compression_config.dart';
import 'context_router.dart';

/// 压缩 [messages] 中指定 role 的消息正文。
///
/// 只改正文，保留 `toolCalls` / `toolCallId` / `cacheable` / `images` /
/// `thinkingBlocks`；不增删消息。默认只处理 `tool`。返回新列表。
Future<List<LlmMessage>> compressMessages(
  List<LlmMessage> messages, {
  ContextCompressionConfig? config,
  CcrStore? store,
  List<ContentCompressor>? compressors,
  Set<String> roles = const <String>{'tool'},
}) async {
  if (messages.isEmpty) return messages;
  final ContextCompressionConfig resolved =
      config ?? const ContextCompressionConfig();
  final ContextRouter router = ContextRouter(
    config: resolved,
    store: store ??
        CcrMemoryStore(
          maxEntries: resolved.ccrMaxEntries,
          ttl: resolved.ccrTtl,
        ),
    compressors: compressors,
  );
  final List<LlmMessage> output = <LlmMessage>[];
  for (final LlmMessage message in messages) {
    if (!roles.contains(message.role) || message.content.isEmpty) {
      output.add(message);
      continue;
    }
    final result = await router.compress(
      message.content,
      toolName: 'llm_message',
    );
    output.add(result.applied ? _rebuild(message, result.content) : message);
  }
  return output;
}

LlmMessage _rebuild(LlmMessage message, String content) => LlmMessage(
      message.role,
      content,
      toolCalls: message.toolCalls,
      toolCallId: message.toolCallId,
      cacheable: message.cacheable,
      images: message.images,
      thinkingBlocks: message.thinkingBlocks,
    );
