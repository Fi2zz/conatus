/// 屏上记录：把 conatus 会话事件投射为可渲染的消息流。
///
/// 与参考的「气泡镜像」不同，这里直接以 [SessionEvent] 为唯一事实源：
/// 用户 / 助手 / 工具 / 计划各自渲染成一行，绑定会话时回放历史事件，
/// 之后由 [apply] 增量追加，因此与持久化历史天然一致。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';

import 'tui_message.dart';
import 'tui_skill_command.dart';

/// 屏上记录。
class Transcript {
  /// 屏上消息（按发生顺序）。
  final List<TuiMessage> messages = <TuiMessage>[];

  /// `/help` 弹出的帮助消息（Esc 可关闭）；null = 未打开。
  TuiMessage? help;

  /// 清空屏上记录（不改动会话数据）。
  void clear() {
    messages.clear();
    help = null;
  }

  /// 追加一条消息。
  void add(TuiRole role, String text) => messages.add(TuiMessage(role, text));

  /// 打开帮助弹出并记录引用，供 [closeHelp] 移除；已打开时先关闭旧的。
  void openHelp(String text) {
    closeHelp();
    help = TuiMessage(TuiRole.system, text);
    messages.add(help!);
  }

  /// 关闭帮助弹出；未打开返回 false。
  bool closeHelp() {
    final TuiMessage? message = help;
    if (message == null) {
      return false;
    }
    messages.remove(message);
    help = null;
    return true;
  }

  /// 绑定会话：按持久化事件回放整段历史。
  void rebuildFrom(Session session) {
    messages.clear();
    help = null;
    for (final SessionEvent event in session.events) {
      apply(event);
    }
  }

  /// 增量投射一条会话事件。
  void apply(SessionEvent event) {
    final Object? data = event.data;
    switch (event.type) {
      case kUserMessageEvent:
        add(TuiRole.user, collapseSkillPrompt(_text(data)));
      case kAssistantMessageEvent:
        final String text = _text(data);
        if (text.trim().isNotEmpty) {
          add(TuiRole.assistant, text);
          return;
        }
        for (final LlmToolCall call in _toolCalls(data)) {
          add(TuiRole.stage, '· 调用工具 ${call.name}');
        }
      case kToolResultEvent:
        final String name = _field(data, 'name');
        final bool failed = data is Map && data['isError'] == true;
        final String mark = failed ? '✗' : '✓';
        add(TuiRole.tool, '· 工具 $mark $name${_preview(data)}');
      case kPlanEvent:
        add(TuiRole.stage, '· 计划已更新');
      default:
        // 其余事件（含自定义）不投射。
        return;
    }
  }

  static String _text(Object? data) => _field(data, 'text');

  static String _field(Object? data, String key) {
    if (data is Map) {
      final Object? value = data[key];
      return value == null ? '' : '$value';
    }
    return '';
  }

  static List<LlmToolCall> _toolCalls(Object? data) {
    if (data is Map) return toolCallsFromJson(data['toolCalls']);
    return const <LlmToolCall>[];
  }

  static String _preview(Object? data) {
    if (data is! Map) return '';
    final String content = '${data['content'] ?? ''}'.trim();
    if (content.isEmpty) return '';
    final String firstLine = content.split('\n').first.trim();
    final String trimmed =
        firstLine.length > 80 ? '${firstLine.substring(0, 80)}…' : firstLine;
    return ' → $trimmed';
  }
}
