/// 「模型可见即已记录」不变式：日志里每条 `llm/request` 都必须能从日志本身重建。
///
/// 目的是让 Session Log 真正可作轨迹回放：凡是进入模型的内容，都能在日志里找到
/// 出处，不存在绕过日志的上下文注入。
library;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'agent_events.dart';
import 'agent_types.dart';

/// 检查「模型可见即已记录」不变式，返回全部违规描述（空列表表示通过）。
///
/// 对日志中每条 [kLlmRequestEvent]，用 [deriveAgentMessages] 从**该事件之前**已
/// 记录的事件重建会话消息，再与请求负载逐条比对。
///
/// 比对范围是请求里**首个非 system 消息**起的部分：system prompt 由会话状态、
/// 长记忆与滚动摘要现场装配，不属于「日志可重建」的范畴。
List<String> checkModelVisibleInvariant(Iterable<SessionEvent> events) {
  final List<SessionEvent> all = List<SessionEvent>.of(events);
  final List<String> violations = <String>[];
  for (int index = 0; index < all.length; index++) {
    if (all[index].type != kLlmRequestEvent) continue;
    violations.addAll(_checkRequest(all, index));
  }
  return violations;
}

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

List<String> _checkRequest(List<SessionEvent> all, int index) {
  final List<Object?>? raw = _loggedMessages(all[index].data);
  if (raw == null) {
    return <String>['第 $index 条 $kLlmRequestEvent 缺少 messages 负载'];
  }
  return _compareRequests(
    index,
    deriveAgentMessages(all.sublist(0, index)),
    _conversation(raw),
  );
}

List<String> _compareRequests(
  int index,
  List<LlmMessage> expected,
  List<Object?> logged,
) {
  final List<String> problems = <String>[];
  if (expected.length != logged.length) {
    problems.add(
      '第 $index 条 $kLlmRequestEvent：日志可重建 ${expected.length} 条会话消息，'
      '实际发出 ${logged.length} 条',
    );
  }
  for (int i = 0; i < expected.length && i < logged.length; i++) {
    if (!_matches(expected[i], logged[i])) {
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

String? _roleOf(Object? message) => message is Map<Object?, Object?>
    ? message['role'] as String?
    : null;
