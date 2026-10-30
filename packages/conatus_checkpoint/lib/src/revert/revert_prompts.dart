/// 从会话事件里推算「撤销 N 轮」的切点与被撤回的 prompt 文本。
///
/// 有检查点时切点来自检查点清单的 `lastEventId`；`[checkpoint] enabled = false`
/// 时没有轮次边界，只能按 `user/message` 事件数倒推（每轮一条用户消息）。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

/// 撤销 [count] 轮对话的切点：倒数第 [count] 条用户消息之前的事件 id。
///
/// 轮次不够时返回 `null`（表示回滚全部对话）；切点在最前面时同样返回 `null`
/// （`Session.fork` 以 null 表示「从会话开头起」，调用方按全新空会话处理）。
String? revertCutBefore(Session session, int count) {
  final List<SessionEvent> events = session.events;
  int remaining = count;
  for (int i = events.length - 1; i >= 0; i--) {
    if (events[i].type != kUserMessageEvent) continue;
    remaining--;
    if (remaining == 0) return i == 0 ? null : events[i - 1].id;
  }
  return null;
}

/// [cut] 之后（不含）的 user/message 文本，按出现顺序。
///
/// [cut] 为 `null` 或不在事件里时返回全部用户 prompt 文本——此时撤销的就是
/// 整段对话。空文本（无 `text` 字段）忽略。
List<String> revertPromptsAfter(Session session, String? cut) {
  final List<SessionEvent> events = session.events;
  final int cutIndex = cut == null
      ? -1
      : events.indexWhere((SessionEvent event) => event.id == cut);
  return <String>[
    for (int i = cutIndex + 1; i < events.length; i++)
      if (events[i].type == kUserMessageEvent) _eventText(events[i]),
  ]..removeWhere((String text) => text.isEmpty);
}

/// 会话里的用户消息条数（`/undo` 的「还有东西可撤吗」判据）。
int revertPromptCount(Session session) => session.events
    .where((SessionEvent event) => event.type == kUserMessageEvent)
    .length;

String _eventText(SessionEvent event) {
  final Object? data = event.data;
  if (data is Map) {
    final Object? text = data['text'];
    return text == null ? '' : '$text';
  }
  return '';
}
