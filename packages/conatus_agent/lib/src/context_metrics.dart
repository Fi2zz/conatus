/// context-metrics：上下文体量的粗粒度估算。
///
/// 口径是「约 4 个字符 1 个 token」，只用于**相对度量**（压缩前后对比、缓存
/// 前缀大小、趋势观察），不用于计费或硬预算判断——真实 token 数由各提供方的
/// 分词器决定，且中文、代码与 JSON 的字符/token 比差异很大。
library;

import 'package:conatus_llm/conatus_llm.dart';

/// 粗略估算 [text] 的 token 数：字符数除以 4 向上取整，空串为 0。
int estimateTokens(String text) => text.isEmpty ? 0 : (text.length + 3) ~/ 4;

/// 粗略估算一组消息的 token 数：逐条累加 role、content 与工具调用。
///
/// 工具调用计入 id、名字与参数串，因为它们在请求体里同样是真实负载。
int estimateMessagesTokens(List<LlmMessage> messages) {
  int total = 0;
  for (final LlmMessage message in messages) {
    total += estimateTokens(message.role) + estimateTokens(message.content);
    for (final LlmToolCall call in message.toolCalls) {
      total += estimateTokens(call.id) +
          estimateTokens(call.name) +
          estimateTokens(call.arguments);
    }
  }
  return total;
}
