import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.script);

  final List<LlmResult> script;
  final List<List<LlmMessage>> calls = <List<LlmMessage>>[];

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls.add(List<LlmMessage>.of(messages));
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

LlmResult _call(String id, String name) => LlmResult(
      content: '',
      provider: 'scripted',
      model: 'm',
      toolCalls: <LlmToolCall>[LlmToolCall(id: id, name: name)],
    );

/// 构造挂有续行驱动器的 AgentLoop；驱动器的 agent 即返回的 loop 自身，
/// 续行才真正递归回同一 loop（与 `provideGoal` 的挂载方式一致）。
AgentLoop _loopWithGoal(
  LlmProvider llm,
  ToolRegistry tools,
  GoalService service, {
  Session? session,
}) {
  final AgentLoop loop = AgentLoop(llm: llm, tools: tools, session: session);
  loop.goalDriver = GoalRoundDriver(goal: service, agent: loop);
  return loop;
}

/// 仅用于 shouldContinue 决策测试的驱动器（不会真正 run）。
GoalRoundDriver _driverFor(GoalService service) => GoalRoundDriver(
    goal: service, agent: AgentLoop(llm: _NullLlm(), tools: ToolRegistry()));

void main() {
  group('GoalRoundDriver.shouldContinue', () {
    Future<GoalContinuation> decisionFor(GoalStatus? status,
        {int round = 0, int maxRounds = 4}) async {
      final DefaultGoalService service = DefaultGoalService();
      if (status != null) {
        await service.create('g', maxRounds: maxRounds);
        for (int i = 0; i < round; i++) {
          await service.advanceRound();
        }
        switch (status) {
          case GoalStatus.paused:
            await service.pause();
          case GoalStatus.blocked:
            await service.block('卡住');
          case GoalStatus.completed:
            await service.complete();
          case GoalStatus.cleared:
            await service.clear();
          case GoalStatus.active:
            break;
        }
      }
      return _driverFor(service).shouldContinue();
    }

    test('无目标 wait；active proceed；paused wait；blocked / 终态 stop', () async {
      expect(await decisionFor(null), GoalContinuation.wait);
      expect(await decisionFor(GoalStatus.active), GoalContinuation.proceed);
      expect(await decisionFor(GoalStatus.paused), GoalContinuation.wait);
      expect(await decisionFor(GoalStatus.blocked), GoalContinuation.stop);
      expect(await decisionFor(GoalStatus.completed), GoalContinuation.stop);
      expect(await decisionFor(GoalStatus.cleared), GoalContinuation.wait);
    });

    test('active 但 round 达上限时自动 block 并 stop', () async {
      final DefaultGoalService service = DefaultGoalService();
      await service.create('g', maxRounds: 1);
      await service.advanceRound();

      expect(await _driverFor(service).shouldContinue(), GoalContinuation.stop);
      final Goal goal = service.current!;
      expect(goal.status, GoalStatus.blocked);
      expect(goal.blockReason, kGoalRoundLimitReason);
    });
  });

  group('AgentLoop 集成', () {
    test('无目标不续行：只跑一次', () async {
      final _ScriptedProvider provider =
          _ScriptedProvider(<LlmResult>[_text('你好')]);
      final AgentLoop loop =
          _loopWithGoal(provider, ToolRegistry(), DefaultGoalService());

      final AgentTurn turn = await loop.run('在吗');

      expect(turn.reply, '你好');
      expect(provider.calls, hasLength(1));
    });

    test('active 目标自动续行直到 complete_goal', () async {
      final DefaultGoalService service = DefaultGoalService();
      await service.create('盯机票', maxRounds: 8);
      final _ScriptedProvider provider = _ScriptedProvider(<LlmResult>[
        _text('收到'),
        _call('c1', kCompleteGoalToolName),
        _text('目标完成'),
      ]);
      final ToolRegistry tools = ToolRegistry()
        ..register(CompleteGoalTool(goal: service));
      final AgentLoop loop = _loopWithGoal(provider, tools, service);

      final AgentTurn turn = await loop.run('开始');

      expect(turn.reply, '目标完成');
      expect(provider.calls, hasLength(3));
      expect(service.current!.status, GoalStatus.completed);
      expect(service.current!.round, 1);
    });

    test('续行轮以系统提示注入下一轮', () async {
      final DefaultGoalService service = DefaultGoalService();
      await service.create('盯机票', maxRounds: 8);
      final Session session = Session(id: 's1');
      final _ScriptedProvider provider = _ScriptedProvider(<LlmResult>[
        _text('收到'),
        _call('c1', kCompleteGoalToolName),
        _text('完成'),
      ]);
      final ToolRegistry tools = ToolRegistry()
        ..register(CompleteGoalTool(goal: service));
      final AgentLoop loop =
          _loopWithGoal(provider, tools, service, session: session);

      await loop.run('开始');

      final List<SessionEvent> userEvents = session.events
          .where((SessionEvent e) => e.type == kUserMessageEvent)
          .toList();
      expect(userEvents, hasLength(2));
      final Object? last = userEvents.last.data;
      expect((last as Map<String, Object?>)['text'], kGoalContinuationPrompt);
    });

    test('paused 目标续行等待：只跑一次', () async {
      final DefaultGoalService service = DefaultGoalService();
      await service.create('盯机票');
      await service.pause();
      final _ScriptedProvider provider =
          _ScriptedProvider(<LlmResult>[_text('好的')]);
      final AgentLoop loop = _loopWithGoal(provider, ToolRegistry(), service);

      await loop.run('开始');

      expect(provider.calls, hasLength(1));
    });

    test('maxRounds 跑满自动 block，不再续行', () async {
      final DefaultGoalService service = DefaultGoalService();
      await service.create('盯机票', maxRounds: 1);
      final _ScriptedProvider provider =
          _ScriptedProvider(<LlmResult>[_text('跑一轮')]);
      final AgentLoop loop = _loopWithGoal(provider, ToolRegistry(), service);

      final AgentTurn turn = await loop.run('开始');

      expect(turn.reply, '跑一轮');
      expect(provider.calls, hasLength(1));
      final Goal goal = service.current!;
      expect(goal.status, GoalStatus.blocked);
      expect(goal.blockReason, kGoalRoundLimitReason);
    });
  });
}

class _NullLlm extends LlmProvider {
  @override
  String get name => 'null';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async =>
      const LlmResult(content: '', provider: 'null', model: 'm');

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
