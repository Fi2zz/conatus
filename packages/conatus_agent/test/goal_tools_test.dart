import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

void main() {
  group('目标工具', () {
    test('create_goal 创建成功返回口语化确认；max_rounds 生效', () async {
      final DefaultGoalService service = DefaultGoalService();
      final CreateGoalTool tool = CreateGoalTool(goal: service);
      final ToolResult result = await tool.call(const ToolContext(ToolCall(
        name: kCreateGoalToolName,
        arguments: <String, Object?>{'text': '盯机票', 'max_rounds': 8},
      )));

      expect(result.isError, isFalse);
      expect(result.content, contains('持续关注'));
      expect(service.current!.text, '盯机票');
      expect(service.current!.maxRounds, 8);
    });

    test('create_goal 已有目标时失败并携带错误码', () async {
      final DefaultGoalService service = DefaultGoalService();
      final CreateGoalTool tool = CreateGoalTool(goal: service);
      await tool.call(const ToolContext(ToolCall(
        name: kCreateGoalToolName,
        arguments: <String, Object?>{'text': 'A'},
      )));
      final ToolResult result = await tool.call(const ToolContext(ToolCall(
        name: kCreateGoalToolName,
        arguments: <String, Object?>{'text': 'B'},
      )));

      expect(result.isError, isTrue);
      expect(result.error!.code, 'already_exists');
    });

    test('edit_goal 更新文本；无目标时失败', () async {
      final DefaultGoalService service = DefaultGoalService();
      final EditGoalTool tool = EditGoalTool(goal: service);
      final ToolResult missing = await tool.call(const ToolContext(ToolCall(
        name: kEditGoalToolName,
        arguments: <String, Object?>{'text': 'x'},
      )));
      expect(missing.isError, isTrue);
      expect(missing.error!.code, 'invalid_status');

      await service.create('盯机票');
      final ToolResult result = await tool.call(const ToolContext(ToolCall(
        name: kEditGoalToolName,
        arguments: <String, Object?>{'text': '盯明天机票'},
      )));
      expect(result.isError, isFalse);
      expect(result.content, contains('已更新'));
      expect(service.current!.text, '盯明天机票');
    });

    test('complete_goal 成功；clear_goal 风险 medium 且走确认', () async {
      final AutoApproval approval = AutoApproval(true);
      final DefaultGoalService service = DefaultGoalService(approval: approval);
      final CompleteGoalTool complete = CompleteGoalTool(goal: service);
      final ClearGoalTool clear = ClearGoalTool(goal: service);
      expect(clear.riskLevel, ToolRisk.medium);

      final ToolResult missing = await complete
          .call(const ToolContext(ToolCall(name: kCompleteGoalToolName)));
      expect(missing.isError, isTrue);

      await service.create('g');
      final ToolResult done = await complete
          .call(const ToolContext(ToolCall(name: kCompleteGoalToolName)));
      expect(done.isError, isFalse);
      expect(service.current!.status, GoalStatus.completed);

      final ToolResult cleared = await clear
          .call(const ToolContext(ToolCall(name: kClearGoalToolName)));
      expect(cleared.isError, isFalse);
      expect(service.current, isNull);
      expect(approval.requests, 2);
    });

    test('审批拒绝时 clear 返回 cancelled 失败', () async {
      final DefaultGoalService service =
          DefaultGoalService(approval: AutoApproval(false));
      final ClearGoalTool clear = ClearGoalTool(goal: service);
      await service.create('g');

      final ToolResult result = await clear
          .call(const ToolContext(ToolCall(name: kClearGoalToolName)));

      expect(result.isError, isTrue);
      expect(result.error!.code, 'cancelled');
      expect(service.current!.status, GoalStatus.active);
    });
  });

  group('goal 段注入', () {
    test('创建时注入 order 50 段；清除后撤销；文本随状态求值', () async {
      final SystemPrompt prompt = SystemPrompt();
      final DefaultGoalService service = DefaultGoalService(prompt: prompt);
      expect(prompt.sections, isEmpty);

      await service.create('盯机票', maxRounds: 4);
      expect(
          prompt.sections.map((PromptSection s) => s.name), <String>['goal']);
      expect(prompt.sections.single.order, 50);
      expect(prompt.sections.single.text(), '[当前目标]\n盯机票');

      await service.advanceRound();
      expect(prompt.sections.single.text(), '[当前目标]\n盯机票\n进度：第 1 / 4 轮');

      await service.clear();
      expect(prompt.sections, isEmpty);
    });

    test('恢复目标时注入段，不重复写事件', () async {
      final Session session = Session(id: 's1');
      final DefaultGoalService first = DefaultGoalService(session: session);
      await first.create('盯机票');
      final SystemPrompt prompt = SystemPrompt();

      final DefaultGoalService restored =
          DefaultGoalService(session: session, prompt: prompt);
      expect(restored.current!.text, '盯机票');
      expect(prompt.sections.single.text(), '[当前目标]\n盯机票');
      expect(
        session.events.where((SessionEvent e) => e.type == kGoalEvent),
        hasLength(1),
      );
    });
  });

  group('provideGoal 装配', () {
    test('注册四个工具并随上下文释放撤销', () {
      final Context ctx = Context.root();
      final ToolRegistry registry = provideTools(ctx);
      final GoalService goal = provideGoal(ctx);

      expect(ctx.goal, same(goal));
      expect(registry.get(kCreateGoalToolName), isNotNull);
      expect(registry.get(kEditGoalToolName), isNotNull);
      expect(registry.get(kCompleteGoalToolName), isNotNull);
      expect(registry.get(kClearGoalToolName), isNotNull);

      ctx.dispose();
      expect(registry.length, 0);
    });

    test('与 agentLoop 齐备时挂载驱动器，dispose 后摘除', () {
      final Context ctx = Context.root();
      final ToolRegistry tools = provideTools(ctx);
      provideGoal(ctx);
      final AgentLoop agent = AgentLoop(llm: _SilentLlm(), tools: tools);
      ctx.provide('agentLoop', agent);

      expect(agent.goalDriver, isNotNull);

      ctx.dispose();
      expect(agent.goalDriver, isNull);
    });
  });

  group('telemetry 埋点', () {
    test('create / edit / pause / resume / block / complete / clear 序列',
        () async {
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      final DefaultGoalService service =
          DefaultGoalService(telemetry: telemetry);

      await service.create('g');
      await service.edit('g2');
      await service.pause();
      await service.resume();
      await service.block('卡住');
      await service.complete();
      await service.clear();

      expect(telemetry.recent.map((TelemetryEvent e) => e.name), <String>[
        'goal.created',
        'goal.edited',
        'goal.paused',
        'goal.resumed',
        'goal.blocked',
        'goal.completed',
        'goal.cleared',
      ]);
      expect(telemetry.recent.first.data['status'], 'active');
    });

    test('advanceRound 发 goal.advanced，到限自动 block 发 goal.blocked', () async {
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      final DefaultGoalService service =
          DefaultGoalService(telemetry: telemetry);
      await service.create('g', maxRounds: 1);

      await service.advanceRound();

      expect(telemetry.recent.map((TelemetryEvent e) => e.name),
          <String>['goal.created', 'goal.blocked']);
    });
  });
}

class _SilentLlm extends LlmProvider {
  @override
  String get name => 'silent';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async =>
      const LlmResult(content: '', provider: 'silent', model: 'm');

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
