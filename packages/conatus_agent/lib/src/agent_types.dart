/// Agent Loop 的类型词汇：事件名、工具步骤与一轮结局。
///
/// 会话以事件记录一轮轮对话（[kUserMessageEvent] / [kAssistantMessageEvent] /
/// [kToolResultEvent]）；事件还原、压缩与 system 装配见 `agent_events.dart`。
library;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';

/// 用户消息事件类型。
const String kUserMessageEvent = 'user/message';

/// 助手消息事件类型（可携带工具调用）。
const String kAssistantMessageEvent = 'assistant/message';

/// 工具结果事件类型。
const String kToolResultEvent = 'tool/result';

/// 一次工具调用在循环中的步骤记录。
class AgentStep {
  const AgentStep({required this.call, required this.result});

  /// 模型请求的调用。
  final LlmToolCall call;

  /// 工具执行结局。
  final ToolResult result;
}

/// 一轮 Agent 循环的结局。
class AgentTurn {
  const AgentTurn({
    required this.reply,
    required this.steps,
    required this.messages,
  });

  /// 最终文本回复。
  final String reply;

  /// 本轮内的工具调用步骤。
  final List<AgentStep> steps;

  /// 本轮结束时的完整消息序列。
  final List<LlmMessage> messages;
}
