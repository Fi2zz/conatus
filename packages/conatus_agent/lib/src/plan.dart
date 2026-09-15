/// planning 插件：Agent 先产出结构化计划，持久化到会话，再进入执行。
/// 计划以 `plan/updated` 事件追加进 [Session]（append-only，取最后一条为当前
/// 计划）。`plan_write` 工具供规划阶段写入；[runPlanningPhase] 在 Agent Loop
/// 里替模型跑一次「只允许 plan_write」的规划轮。
library;

import 'dart:convert';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';

/// 计划变更事件类型。
const String kPlanEvent = 'plan/updated';

/// 规划工具名。
const String kPlanToolName = 'plan_write';

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

/// `plan_write` 工具：写入/更新当前会话的计划。
class PlanTool extends Tool {
  PlanTool({required this.session});

  /// 计划持久化到的会话。
  final Session session;

  @override
  String get name => kPlanToolName;

  @override
  String get description => '制定或更新当前任务的执行计划（目标 + 有序步骤）。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('goal', required: true, description: '任务目标'),
        ParamSpec.array(
          'steps',
          items: ParamSpec.string('item'),
          description: '按顺序的步骤',
        ),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String goal = ctx.str('goal');
    final List<PlanStep> steps = <PlanStep>[];
    final List<Object?> raw = ctx.array('steps') ?? const <Object?>[];
    for (int i = 0; i < raw.length; i++) {
      final String text = '${raw[i]}'.trim();
      if (text.isNotEmpty) steps.add(PlanStep(id: 's${i + 1}', text: text));
    }
    final Plan plan = Plan(goal: goal, steps: steps);
    writePlan(session, plan);
    return ToolResult.success(plan.summary(), value: plan.toJson());
  }
}

/// 规划轮：只下发 `plan_write`，让模型先产出计划；写好后刷新 system 消息。
///
/// 返回是否真正跑了规划（未注册 `plan_write` 时返回 false）。
Future<bool> runPlanningPhase({
  required LlmProvider llm,
  required ToolRegistry tools,
  required Session session,
  required List<LlmMessage> messages,
  required String Function() systemText,
}) async {
  final Map<String, Object?>? schema = tools.describeOne(kPlanToolName);
  if (schema == null) return false;
  final List<LlmMessage> planning = <LlmMessage>[
    LlmMessage(
      'system',
      '${systemText()}\n\n先制定一个简洁的执行计划：只调用 $kPlanToolName 工具，'
          '不要直接回答用户。',
    ),
    ...messages.skip(1),
  ];
  final LlmResult result =
      await llm.chat(planning, tools: <Map<String, Object?>>[schema]);
  for (final LlmToolCall call in result.toolCalls) {
    if (call.name != kPlanToolName) continue;
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

/// 把 `plan_write` 工具注册到 `ctx.tools`。
PlanTool providePlanTool(
  Context ctx, {
  required Session session,
  ToolRegistry? tools,
}) {
  final ToolRegistry registry = tools ?? ctx.tools;
  final PlanTool tool = PlanTool(session: session);
  ctx.effect(() => registry.register(tool));
  return tool;
}
