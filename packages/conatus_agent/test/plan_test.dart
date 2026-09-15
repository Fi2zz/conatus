import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
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
  group('Plan / PlanTool', () {
    test('plan_write 写入并可由 readPlan 还原', () async {
      final Session session = Session(id: 's1');
      final PlanTool tool = PlanTool(session: session);

      final ToolResult result = await tool.call(const ToolContext(
        ToolCall(
          name: 'plan_write',
          arguments: <String, Object?>{
            'goal': '查三家公司',
            'steps': <Object?>['查A', '查B', '查C'],
          },
        ),
      ));

      expect(result.isError, isFalse);
      final Plan? plan = readPlan(session);
      expect(plan, isNotNull);
      expect(plan!.goal, '查三家公司');
      expect(
          plan.steps.map((PlanStep s) => s.text), <String>['查A', '查B', '查C']);
      expect(plan.summary(), contains('1. [ ] 查A'));
      expect(session.events.single.type, kPlanEvent);
    });

    test('readPlan 无计划时为 null；planSection 为空串', () {
      final Session session = Session(id: 's1');
      expect(readPlan(session), isNull);
      expect(planSection(session), isEmpty);
      expect(planSection(null), isEmpty);
    });

    test('providePlanTool 注册 plan_write 并随上下文释放撤销', () {
      final Context ctx = Context.root();
      provideTools(ctx);
      providePlanTool(ctx, session: Session(id: 's1'));

      expect(ctx.tools.get(kPlanToolName), isNotNull);
      ctx.dispose();
    });
  });

  group('AgentLoop 规划阶段', () {
    test('无计划时先跑规划轮，执行阶段注入 [当前计划]', () async {
      final Session session = Session(id: 's1');
      final ToolRegistry tools = ToolRegistry()
        ..register(PlanTool(session: session));
      final _ScriptedProvider provider = _ScriptedProvider(<LlmResult>[
        _call('p1', kPlanToolName, '{"goal":"查三家公司","steps":["查A","查B","查C"]}'),
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
      // 规划轮只下发 plan_write。
      expect(provider.calls, hasLength(2));
      expect(provider.toolSchemas.first!.single['name'], kPlanToolName);
      // 执行轮 system 里带上了计划。
      expect(provider.calls.last.first.content, contains('[当前计划]'));
      expect(provider.calls.last.first.content, contains('查A'));
    });

    test('已有计划时不重复规划', () async {
      final Session session = Session(id: 's1');
      writePlan(session, const Plan(goal: '旧目标'));
      final ToolRegistry tools = ToolRegistry()
        ..register(PlanTool(session: session));
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
