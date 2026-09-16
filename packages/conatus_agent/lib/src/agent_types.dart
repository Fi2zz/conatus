/// Agent Loop 的类型词汇：工具步骤与一轮结局，以及 Session Log 的派生事件名。
///
/// 会话以事件记录一轮轮对话（[kUserMessageEvent] / [kAssistantMessageEvent] /
/// [kToolResultEvent]）；这三个消息事件名由 `conatus_foundation` 拥有，此处转出。
/// 事件还原、压缩与 system 装配见 `agent_events.dart`。
library;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';

// 消息事件名由 `conatus_foundation` 的会话词汇拥有（压缩与 Agent Loop 都要
// 按事件类型判断），此处只做转出，保持 `agent_types.dart` 的既有导入面。
export 'package:conatus_foundation/conatus_foundation.dart'
    show kAssistantMessageEvent, kToolResultEvent, kUserMessageEvent;

/// 模型请求事件类型。
///
/// Session Log 的**派生事件**（非模型可见）：记录真正发给模型的消息与工具表，
/// 用于「模型可见即可从日志重建」的不变式校验。`deriveAgentMessages` 只识别
/// 三类消息事件，因此它们不会污染请求派生。
const String kLlmRequestEvent = 'llm/request';

/// 模型响应事件类型（Session Log 的派生事件）。
const String kLlmResponseEvent = 'llm/response';

/// 工具调用事件类型（Session Log 的派生事件，早于工具执行）。
const String kToolCallEvent = 'tool/call';

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
