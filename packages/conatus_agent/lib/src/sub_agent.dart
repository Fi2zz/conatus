/// sub-agent 插件：把子任务委托给隔离的子 Agent 执行。
///
/// [SpawnAgentTool]（`spawn_agent`）是一个普通工具：主 Agent 调用它时，本插件
/// 在宿主上下文下派生一个隔离子上下文，创建独立的 [Session] 与受限的
/// [ToolRegistry]，跑一个独立的 [AgentLoop]，只把最终结果回传主 Agent。子上下文
/// 随宿主释放，宿主被取消/释放时子 Agent 一并终止。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'agent_loop.dart';
import 'agent_types.dart';

/// 子 Agent 的默认人设：只完成交办的一件事，只回结论。
const String kDefaultSubAgentPrompt = '你是内部子助手，只完成交办的一件事。只依据工具返回的事实作答，禁止编造；'
    '完成后直接给出结论简报（尽量简短），不要寒暄、不要反问用户。';

/// 一次子 Agent 委托的结局。
class SubAgentResult {
  const SubAgentResult({
    required this.status,
    required this.output,
    this.rounds = 0,
    this.toolCalls = const <String>[],
  });

  /// 状态：`success` / `failed`。
  final String status;

  /// 结论简报（成功）或失败说明。
  final String output;

  /// 工具调用步数。
  final int rounds;

  /// 子 Agent 用过的工具名（按序）。
  final List<String> toolCalls;

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'status': status,
        'output': output,
        'rounds': rounds,
        'tool_calls': toolCalls,
      };
}

/// `spawn_agent`：把一段自包含的任务委托给隔离子 Agent。
class SpawnAgentTool extends Tool {
  SpawnAgentTool({
    required this.host,
    required this.llm,
    required this.tools,
    this.defaultTools,
    this.maxRounds = 8,
    this.subAgentPrompt = kDefaultSubAgentPrompt,
    this.systemPrompt,
  });

  /// 宿主上下文：子上下文在其下派生，随宿主释放。
  final Context host;

  /// 子 Agent 使用的模型（与主 Agent 同一实例，可换）。
  final LlmProvider llm;

  /// 主注册表：用于按白名单取工具实例。
  final ToolRegistry tools;

  /// 未显式传 `tools` 时的默认白名单；缺省取主注册表里非 high 且非本工具。
  final List<String>? defaultTools;

  /// 默认最大模型调用步数。
  final int maxRounds;

  /// 子 Agent 的兜底人设。
  final String subAgentPrompt;

  /// 子 Agent 的 system prompt 注册表；缺省不用（隔离）。
  final SystemPrompt? systemPrompt;

  int _seq = 0;

  @override
  String get name => 'spawn_agent';

  @override
  String get description => '把一个自包含的子任务委托给独立的子 Agent 执行，只回结论。';

  @override
  ToolRisk get riskLevel => ToolRisk.medium;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('task', required: true, description: '自包含的子任务描述'),
        ParamSpec.array(
          'tools',
          items: ParamSpec.string('item'),
          description: '允许子 Agent 使用的工具名（白名单）',
        ),
        ParamSpec.integer('max_rounds', description: '子 Agent 最大步数'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String task = ctx.str('task');
    final int rounds = ctx.integer('max_rounds') ?? maxRounds;
    final SubAgentResult result = await run(
      task,
      allowed: _allowedTools(ctx.array('tools')),
      maxRounds: rounds,
    );
    return ToolResult.success(result.output, value: result.toJson());
  }

  /// 跑一次委托。子 Agent 的失败也收敛为 [SubAgentResult]（status=failed）。
  Future<SubAgentResult> run(
    String task, {
    required Set<String> allowed,
    required int maxRounds,
  }) async {
    _seq++;
    final ToolRegistry childTools = ToolRegistry();
    for (final String name in allowed) {
      final Tool? tool = tools.get(name);
      if (tool != null) childTools.register(tool);
    }
    final Session childSession =
        Session(id: 'subagent-$_seq-${DateTime.now().microsecondsSinceEpoch}');
    final Context child = host.plugin('subagent$_seq', (Context c) {
      c.onDispose(childSession.close);
    });
    try {
      final AgentTurn turn = await AgentLoop(
        llm: llm,
        tools: childTools,
        session: childSession,
        systemPrompt: systemPrompt,
        defaultSystemPrompt: subAgentPrompt,
        maxSteps: maxRounds,
      ).run(task);
      return SubAgentResult(
        status: 'success',
        output: turn.reply,
        rounds: turn.steps.length,
        toolCalls: <String>[for (final AgentStep s in turn.steps) s.call.name],
      );
    } catch (error) {
      return SubAgentResult(status: 'failed', output: '子 Agent 失败：$error');
    } finally {
      child.dispose();
    }
  }

  Set<String> _allowedTools(List<Object?>? requested) {
    if (requested != null && requested.isNotEmpty) {
      return <String>{
        for (final Object? item in requested)
          if (tools.get('$item') != null && '$item' != name) '$item',
      };
    }
    if (defaultTools != null) {
      return <String>{
        for (final String n in defaultTools!)
          if (tools.get(n) != null && n != name) n,
      };
    }
    return <String>{
      for (final String n in tools.names)
        if (n != name && tools.get(n)!.riskLevel != ToolRisk.high) n,
    };
  }
}

/// 把 `spawn_agent` 工具注册到宿主上下文的 `ctx.tools`。
SpawnAgentTool provideSpawnAgent(
  Context ctx, {
  Context? host,
  LlmProvider? llm,
  ToolRegistry? tools,
  List<String>? defaultTools,
  int maxRounds = 8,
  String subAgentPrompt = kDefaultSubAgentPrompt,
  SystemPrompt? systemPrompt,
}) {
  final ToolRegistry registry = tools ?? ctx.tools;
  final SpawnAgentTool tool = SpawnAgentTool(
    host: host ?? ctx,
    llm: llm ?? ctx.require<LlmProvider>('llm'),
    tools: registry,
    defaultTools: defaultTools,
    maxRounds: maxRounds,
    subAgentPrompt: subAgentPrompt,
    systemPrompt: systemPrompt,
  );
  ctx.effect(() => registry.register(tool));
  return tool;
}
