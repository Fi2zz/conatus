/// Agent Loop 的事件派生与上下文装配：把会话事件还原为模型消息、压缩、
/// 组装 system，并派生技能轨迹。
library;

import 'dart:convert';
import 'package:conatus_compaction/conatus_compaction.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'plan.dart';

/// 把会话事件日志还原为模型消息序列。
///
/// 只识别三类事件；其余事件忽略。[assistant] 事件若带 `toolCalls`，还原为
/// 助手工具调用消息；[tool] 事件还原为与 `callId` 配对的工具结果消息。
List<LlmMessage> deriveAgentMessages(Iterable<SessionEvent> events) {
  final List<LlmMessage> messages = <LlmMessage>[];
  for (final SessionEvent event in events) {
    final Object? data = event.data;
    if (data is! Map) continue;
    switch (event.type) {
      case kUserMessageEvent:
        messages.add(LlmMessage(
          'user',
          '${data['text'] ?? ''}',
          images: imagesFromJson(data['images']),
        ));
      case kAssistantMessageEvent:
        messages.add(LlmMessage(
          'assistant',
          '${data['text'] ?? ''}',
          toolCalls: toolCallsFromJson(data['toolCalls']),
        ));
      case kToolResultEvent:
        messages.add(LlmMessage(
          'tool',
          '${data['content'] ?? ''}',
          toolCallId: '${data['callId'] ?? ''}',
        ));
    }
  }
  return messages;
}

/// 把事件里的 `images` 负载还原为 [LlmImage] 列表。
List<LlmImage> imagesFromJson(Object? raw) {
  if (raw is! List) return const <LlmImage>[];
  final List<LlmImage> images = <LlmImage>[];
  for (final Object? item in raw) {
    if (item is! Map) continue;
    final Object? mime = item['mimeType'];
    final Object? data = item['base64Data'];
    if (mime is! String || data is! String) continue;
    images.add(LlmImage(mimeType: mime, base64Data: data));
  }
  return images;
}

/// 把 [LlmImage] 列表序列化为事件负载。
List<Map<String, Object?>> imagesToJson(List<LlmImage> images) =>
    <Map<String, Object?>>[
      for (final LlmImage image in images)
        <String, Object?>{
          'mimeType': image.mimeType,
          'base64Data': image.base64Data,
        },
    ];

/// 把事件里的 `toolCalls` 负载还原为 [LlmToolCall] 列表。
List<LlmToolCall> toolCallsFromJson(Object? raw) {
  if (raw is! List) return const <LlmToolCall>[];
  final List<LlmToolCall> calls = <LlmToolCall>[];
  for (final Object? item in raw) {
    if (item is! Map) continue;
    final Object? name = item['name'];
    if (name is! String) continue;
    calls.add(LlmToolCall(
      id: '${item['id'] ?? ''}',
      name: name,
      arguments: '${item['arguments'] ?? '{}'}',
    ));
  }
  return calls;
}

/// 把 [LlmToolCall] 列表序列化为事件负载。
List<Map<String, Object?>> toolCallsToJson(List<LlmToolCall> calls) =>
    <Map<String, Object?>>[
      for (final LlmToolCall call in calls)
        <String, Object?>{
          'id': call.id,
          'name': call.name,
          'arguments': call.arguments,
        },
    ];

/// 解析工具调用的原始 JSON 参数串；非法或非对象时返回空表。
Map<String, Object?> parseToolArguments(String raw) {
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is Map) return Map<String, Object?>.from(decoded);
  } on FormatException {
    // 非法 JSON：交给工具参数校验按缺失必填处理。
  }
  return <String, Object?>{};
}

/// 压缩会话时发给模型的指令前缀。
///
/// 摘要请求不是对话窗口，而是把早前事件**转写**成一段文本；Session Log 的
/// 「模型可见即已记录」校验借此前缀识别并跳过它（见 `model_visible_invariant.dart`）。
const String kCompactionSummaryPrompt = '请把下面这段对话压缩成简洁的中文要点（保留事实、结论与未完成事项）：';

/// 用模型把一组会话事件压缩为要点摘要；[previous] 是上一版摘要。
Future<CompactionSummary> summarizeEvents(
  LlmProvider llm,
  List<SessionEvent> events,
  String previous,
) async {
  final StringBuffer buffer = StringBuffer();
  if (previous.isNotEmpty) buffer.writeln('已有摘要：\n$previous\n');
  buffer.writeln(kCompactionSummaryPrompt);
  for (final LlmMessage message in deriveAgentMessages(events)) {
    buffer.writeln('${message.role}: ${message.content}');
  }
  final LlmResult result =
      await llm.chat(<LlmMessage>[LlmMessage('user', buffer.toString())]);
  return CompactionSummary(result.content.trim(),
      provider: result.provider, model: result.model);
}

/// 会话关闭时抛错以中止循环。
void ensureSessionOpen(Session? session) {
  if (session != null && session.closed) {
    throw StateError('会话 "${session.id}" 已关闭，Agent Loop 中止');
  }
}

/// 会话事件的历史窗口（从 [historyStart] 起）。
Iterable<SessionEvent> recentAgentEvents(Session? session, int historyStart) {
  if (session == null) return const <SessionEvent>[];
  final List<SessionEvent> events = session.events;
  return historyStart <= 0 ? events : events.skip(historyStart);
}

/// 按预算压缩会话；返回历史窗口的起点（事件下标）。
Future<int> compactSession({
  required Session? session,
  required CompactionEngine? compactor,
  required LlmProvider llm,
  required int historyStart,
}) async {
  if (compactor == null || session == null) return historyStart;
  final CompactionResult? result = await compactor.compactIfNeeded(
    session,
    (List<SessionEvent> events, String previous) =>
        summarizeEvents(llm, events, previous),
  );
  // 折叠掉的是日志开头的一段，因此窗口起点就是折叠条数（安全切点可能比预算
  // 切点更靠前，不能再用 keepRecent 反推）。
  return result?.compacted ?? historyStart;
}

/// 组装 system 文本：prompt 段与动态上下文 + 历史摘要 + 当前计划 + 相关记忆。
String buildSystemText({
  required String userInput,
  String? defaultSystemPrompt,
  SystemPrompt? systemPrompt,
  CompactionEngine? compactor,
  MemoryStore? memory,
  Session? session,
  int memoryLimit = 5,
}) {
  final StringBuffer buffer = StringBuffer();
  _writePromptBlock(buffer, systemPrompt, defaultSystemPrompt);
  final String? summary = (compactor != null && session != null)
      ? compactor.summaryOf(session.id)
      : null;
  if (summary != null && summary.isNotEmpty) {
    buffer.write('\n\n[历史摘要]\n$summary');
  }
  final String planBlock = planSection(session);
  if (planBlock.isNotEmpty) buffer.write('\n\n$planBlock');
  final List<MemoryEntry> memories =
      memory?.recall(userInput, limit: memoryLimit) ?? const <MemoryEntry>[];
  if (memories.isNotEmpty) {
    buffer.write('\n\n[相关记忆]');
    for (final MemoryEntry entry in memories) {
      buffer.write('\n- ${entry.text}');
    }
  }
  return buffer.toString();
}

/// 写入 prompt 部分：prompt 段 + 动态上下文（上下文为空时不占位）。
void _writePromptBlock(
  StringBuffer buffer,
  SystemPrompt? systemPrompt,
  String? defaultSystemPrompt,
) {
  if (systemPrompt == null) {
    if (defaultSystemPrompt != null) buffer.write(defaultSystemPrompt);
    return;
  }
  final PromptAssembly assembly = systemPrompt.assemble();
  buffer.write(systemPrompt.render(assembly));
  final String contexts = systemPrompt.renderContexts(assembly);
  if (contexts.isNotEmpty) buffer.write('\n\n$contexts');
}
