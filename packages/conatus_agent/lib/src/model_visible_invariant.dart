/// 「模型可见即已记录」不变式：日志里每条 `llm/request` 都必须能从日志本身重建。
///
/// 目的是让 Session Log 真正可作轨迹回放：凡是进入模型的内容，都能在日志里找到
/// 出处，不存在绕过日志的上下文注入。压缩只会**缩短**发给模型的窗口（更早的内容
/// 以摘要形式进入 system prompt），因此请求是可重建消息的尾对齐后缀。
library;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'agent_events.dart';
import 'agent_types.dart';

/// 检查「模型可见即已记录」不变式，返回全部违规描述（空列表表示通过）。
///
/// 对日志中每条 [kLlmRequestEvent]，用 [deriveAgentMessages] 从**该事件之前**已
/// 记录的事件重建会话消息，再与请求负载做尾对齐比对：请求必须是可重建消息的
/// 一个**后缀**（压缩会让 `AgentLoop` 只发最近窗口），且逐条内容一致。请求比
/// 日志可重建的还长，或某条对不上，都说明有内容绕过了日志。
///
/// **不在本校验范围内**的两类请求：
///
/// * 压缩摘要请求（由 `summarizeEvents` 构造，含 [kCompactionSummaryPrompt]）：
///   它把早前事件转写成一段文本，不是对话窗口；
/// * system prompt：由运行时状态（长记忆、滚动摘要、计划）现场装配。
List<String> checkModelVisibleInvariant(Iterable<SessionEvent> events) {
  final List<SessionEvent> all = List<SessionEvent>.of(events);
  final List<String> violations = <String>[];
  for (int index = 0; index < all.length; index++) {
    if (all[index].type != kLlmRequestEvent) continue;
    final List<Object?>? raw = _loggedMessages(all[index].data);
    if (raw == null) {
      violations.add('第 $index 条 $kLlmRequestEvent 缺少 messages 负载');
      continue;
    }
    final List<Object?> logged = _conversation(raw);
    if (_compactionRequest(logged)) continue;
    violations.addAll(
      _compareRequests(
          index, deriveAgentMessages(all.sublist(0, index)), logged),
    );
  }
  return violations;
}

/// 是不是压缩摘要请求：conversation 只有一条含指令前缀的 user 消息。
bool _compactionRequest(List<Object?> logged) =>
    logged.length == 1 &&
    _roleOf(logged.single) == 'user' &&
    _contentOf(logged.single).contains(kCompactionSummaryPrompt);

/// 消息的文本内容；不是 Map 时为 `''`。
String _contentOf(Object? message) =>
    message is Map<Object?, Object?> ? '${message['content']}' : '';

/// 断言不变式，违规时抛 [StateError]（开发模式使用，生产可不启用）。
void assertModelVisibleInvariant(Iterable<SessionEvent> events) {
  final List<String> violations = checkModelVisibleInvariant(events);
  if (violations.isEmpty) return;
  throw StateError('模型可见即已记录不变式被破坏：\n${violations.join('\n')}');
}

/// 递归比较两份 JSON 结构（`Map` / `List` / 标量）。
bool sameJson(Object? left, Object? right) {
  if (left is Map<Object?, Object?> && right is Map<Object?, Object?>) {
    return _sameMap(left, right);
  }
  if (left is List<Object?> && right is List<Object?>) {
    return _sameList(left, right);
  }
  return left == right;
}

bool _sameMap(Map<Object?, Object?> left, Map<Object?, Object?> right) {
  if (left.length != right.length) return false;
  for (final Object? key in left.keys) {
    if (!right.containsKey(key) || !sameJson(left[key], right[key])) {
      return false;
    }
  }
  return true;
}

bool _sameList(List<Object?> left, List<Object?> right) {
  if (left.length != right.length) return false;
  for (int index = 0; index < left.length; index++) {
    if (!sameJson(left[index], right[index])) return false;
  }
  return true;
}

List<String> _compareRequests(
  int index,
  List<LlmMessage> expected,
  List<Object?> logged,
) {
  final int offset = expected.length - logged.length;
  if (offset < 0) {
    return <String>[
      '第 $index 条 $kLlmRequestEvent 实际发出 ${logged.length} 条会话消息，'
          '日志只能重建 ${expected.length} 条',
    ];
  }
  final List<String> problems = <String>[];
  for (int i = 0; i < logged.length; i++) {
    if (!_matches(expected[offset + i], logged[i])) {
      problems.add('第 $index 条 $kLlmRequestEvent 的第 $i 条会话消息无法从日志重建');
    }
  }
  return problems;
}

bool _matches(LlmMessage message, Object? logged) =>
    logged is Map<Object?, Object?> && sameJson(message.toJson(), logged);

List<Object?>? _loggedMessages(Object? data) {
  if (data is! Map<Object?, Object?>) return null;
  final Object? messages = data['messages'];
  return messages is List<Object?> ? messages : null;
}

/// 请求里首个非 system 消息起的部分。
List<Object?> _conversation(List<Object?> messages) {
  int start = 0;
  while (start < messages.length && _roleOf(messages[start]) == 'system') {
    start++;
  }
  return messages.sublist(start);
}

String? _roleOf(Object? message) =>
    message is Map<Object?, Object?> ? message['role'] as String? : null;
