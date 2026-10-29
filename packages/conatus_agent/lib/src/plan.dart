/// planning 插件：Agent 先产出结构化计划，持久化到会话，再进入执行。
/// 计划以 `plan/updated` 事件追加进 [Session]（append-only，取最后一条为当前
/// 计划）。`todowrite` 工具（conatus_code 提供）负责创建与推进；[runPlanningPhase]
/// 在 Agent Loop 里替模型跑一次「只允许 todowrite」的规划轮。
library;

import 'dart:convert';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';

/// 计划变更事件类型。
const String kPlanEvent = 'plan/updated';

/// 规划工具名（与 conatus_code 的 `todowrite` 一致）。
const String kTodoToolName = 'todowrite';

/// 计划的一步。
class PlanStep {
  const PlanStep({required this.id, required this.text, this.done = false});

  /// 步骤 id。
  final String id;

  /// 步骤描述。
  final String text;

  /// 是否已完成。
  final bool done;

  /// 从 JSON 反序列化。
  factory PlanStep.fromJson(Map<String, Object?> json) => PlanStep(
        id: '${json['id'] ?? ''}',
        text: '${json['text'] ?? ''}',
        done: json['done'] == true,
      );

  /// 序列化为 JSON。
  Map<String, Object?> toJson() =>
      <String, Object?>{'id': id, 'text': text, 'done': done};
}

/// 一份执行计划。
class Plan {
  const Plan({required this.goal, this.steps = const <PlanStep>[]});

  /// 任务目标。
  final String goal;

  /// 有序步骤。
  final List<PlanStep> steps;

  /// 从 JSON 反序列化。
  factory Plan.fromJson(Map<String, Object?> json) => Plan(
        goal: '${json['goal'] ?? ''}',
        steps: <PlanStep>[
          for (final Object? item
              in (json['steps'] as List<Object?>?) ?? const <Object?>[])
            if (item is Map) PlanStep.fromJson(Map<String, Object?>.from(item)),
        ],
      );

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'goal': goal,
        'steps': <Map<String, Object?>>[
          for (final PlanStep step in steps) step.toJson(),
        ],
      };

  /// 面向模型/日志的可读摘要。
  String summary() {
    final StringBuffer buffer = StringBuffer('目标：$goal');
    for (int i = 0; i < steps.length; i++) {
      buffer
          .write('\n${i + 1}. [${steps[i].done ? 'x' : ' '}] ${steps[i].text}');
    }
    return buffer.toString();
  }
}

/// 读取会话里最新的计划；没有则返回 `null`。
Plan? readPlan(Session session) {
  for (final SessionEvent event in session.events.reversed) {
    if (event.type != kPlanEvent) continue;
    final Object? data = event.data;
    if (data is Map) return Plan.fromJson(Map<String, Object?>.from(data));
  }
  return null;
}

/// 把计划写入会话（追加一条 `plan/updated` 事件）。
void writePlan(Session session, Plan plan) =>
    session.append(kPlanEvent, data: plan.toJson());

/// 计划注入 system prompt 的片段；无计划时为空串。
String planSection(Session? session) {
  if (session == null) return '';
  final Plan? plan = readPlan(session);
  return plan == null ? '' : '[当前计划]\n${plan.summary()}';
}

/// 规划轮：只下发 `todowrite`，让模型先产出计划；写好后刷新 system 消息。
///
/// 返回是否真正跑了规划（未注册 `todowrite` 时返回 false）。
Future<bool> runPlanningPhase({
  required LlmProvider llm,
  required ToolRegistry tools,
  required Session session,
  required List<LlmMessage> messages,
  required String Function() systemText,
}) async {
  final Map<String, Object?>? schema = tools.describeOne(kTodoToolName);
  if (schema == null) return false;
  final List<LlmMessage> planning = <LlmMessage>[
    LlmMessage(
      'system',
      '${systemText()}\n\n先制定一个简洁的执行计划：只调用 $kTodoToolName 工具，'
          '不要直接回答用户。',
    ),
    ...messages.skip(1),
  ];
  final LlmResult result =
      await llm.chat(planning, tools: <Map<String, Object?>>[schema]);
  for (final LlmToolCall call in result.toolCalls) {
    if (call.name != kTodoToolName) continue;
    await tools.call(ToolCall(
      name: call.name,
      callId: call.id,
      arguments: _parseArguments(call.arguments),
    ));
  }
  if (messages.isNotEmpty) messages[0] = LlmMessage('system', systemText());
  return true;
}

Map<String, Object?> _parseArguments(String raw) {
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is Map) return Map<String, Object?>.from(decoded);
  } on FormatException {
    // 非法 JSON：交给参数校验按缺失必填处理。
  }
  return <String, Object?>{};
}

