import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.script);

  final List<LlmResult> script;
  final List<List<LlmMessage>> calls = <List<LlmMessage>>[];
  final List<List<Map<String, dynamic>>?> toolSchemas =
      <List<Map<String, dynamic>>?>[];

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls.add(List<LlmMessage>.of(messages));
    toolSchemas.add(tools);
    final int index =
        calls.length - 1 < script.length ? calls.length - 1 : script.length - 1;
    return script[index];
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

LlmResult _text(String content) =>
    LlmResult(content: content, provider: 'scripted', model: 'm');

LlmResult _call(String id, String name, String args) => LlmResult(
      content: '',
      provider: 'scripted',
      model: 'm',
      toolCalls: <LlmToolCall>[
        LlmToolCall(id: id, name: name, arguments: args)
      ],
    );

void main() {
  group('Plan 模型', () {
    test('readPlan 无计划时为 null；planSection 为空串', () {
      final Session session = Session(id: 's1');
      expect(readPlan(session), isNull);
      expect(planSection(session), isEmpty);
      expect(planSection(null), isEmpty);
    });
  });

  group('AgentLoop 规划阶段', () {
    test('无计划时先跑规划轮，执行阶段注入 [当前计划]', () async {
      final Session session = Session(id: 's1');
      final ToolRegistry tools = ToolRegistry()
        ..register(_TodoTool(session: session));
      final _ScriptedProvider provider = _ScriptedProvider(<LlmResult>[
        _call(
          'p1',
          kTodoToolName,
          '{"goal":"查三家公司","todos":[{"text":"查A"},{"text":"查B"},{"text":"查C"}]}',
        ),
        _text('查完了'),
      ]);
      final AgentLoop loop = AgentLoop(
        llm: provider,
        tools: tools,
        session: session,
        planning: true,
      );

      final AgentTurn turn = await loop.run('查三家公司最新产品');

      expect(turn.reply, '查完了');
      expect(readPlan(session)!.steps, hasLength(3));
      // 规划轮只下发 todowrite。
      expect(provider.calls, hasLength(2));
      expect(provider.toolSchemas.first!.single['name'], kTodoToolName);
      // 执行轮 system 里带上了计划。
      expect(provider.calls.last.first.content, contains('[当前计划]'));
      expect(provider.calls.last.first.content, contains('查A'));
    });

    test('已有计划时不重复规划', () async {
      final Session session = Session(id: 's1');
      writePlan(session, const Plan(goal: '旧目标'));
      final ToolRegistry tools = ToolRegistry()
        ..register(_TodoTool(session: session));
      final _ScriptedProvider provider =
          _ScriptedProvider(<LlmResult>[_text('好')]);
      final AgentLoop loop = AgentLoop(
        llm: provider,
        tools: tools,
        session: session,
        planning: true,
      );

      await loop.run('继续');

      expect(provider.calls, hasLength(1));
    });
  });
}

/// 测试替身：用 `todowrite` 的 goal + todos 写入计划。
class _TodoTool extends Tool {
  _TodoTool({required this.session});

  final Session session;

  @override
  String get name => kTodoToolName;

  @override
  String get description => '制定或更新执行计划';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('goal', description: '任务目标'),
        ParamSpec.array(
          'todos',
          items: ParamSpec.object(
            'todo',
            properties: <String, ParamSpec>{
              'text': ParamSpec.string('text'),
            },
          ),
        ),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String goal = ctx.str('goal');
    final List<Object?> raw = ctx.array('todos') ?? const <Object?>[];
    final List<PlanStep> steps = <PlanStep>[
      for (int i = 0; i < raw.length; i++)
        PlanStep(
          id: 's${i + 1}',
          text: '${(raw[i] as Map<String, Object?>)['text']}',
        ),
    ];
    final Plan plan = Plan(goal: goal, steps: steps);
    writePlan(session, plan);
    return ToolResult.success(plan.summary(), value: plan.toJson());
  }
}
