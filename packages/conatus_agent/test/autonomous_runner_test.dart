import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

/// 固定文本回复的假模型。
class _EchoProvider implements LlmProvider {
  _EchoProvider(this.reply);

  final String reply;
  int calls = 0;

  @override
  String get name => 'echo';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls++;
    return LlmResult(content: reply, provider: name, model: 'm');
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

/// 首轮发一次工具调用、之后纯文本回复的假模型。
class _ToolProvider implements LlmProvider {
  _ToolProvider(this.toolName);

  final String toolName;

  @override
  String get name => 'tooly';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    final bool first = !messages.any((LlmMessage m) => m.toolCalls.isNotEmpty);
    if (first) {
      return LlmResult(
        content: '',
        provider: name,
        model: 'm',
        toolCalls: <LlmToolCall>[
          LlmToolCall(id: 'c1', name: toolName),
        ],
      );
    }
    return LlmResult(content: 'done', provider: name, model: 'm');
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

/// 可变成本的假预算缝。
class _FakeCostTracker implements CostTracker {
  _FakeCostTracker(this.todayCost);

  @override
  double todayCost;
}

/// 可阻塞的假模型：首轮调用等 [gate] 完成才返回。
class _BlockingProvider implements LlmProvider {
  final Completer<void> gate = Completer<void>();

  @override
  String get name => 'blocky';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    await gate.future;
    return LlmResult(content: 'ok', provider: name, model: 'm');
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

void main() {
  DefaultGoalService goals(Session session) =>
      DefaultGoalService(session: session);

  AgentLoop agent(LlmProvider llm, Session session, {ToolRegistry? tools}) =>
      AgentLoop(llm: llm, tools: tools ?? ToolRegistry(), session: session);

  DefaultAutonomousRunner makeRunner(
    Session session,
    DefaultGoalService goal, {
    AutonomousPolicy? policy,
    CostTracker? costTracker,
    Approval? approval,
    Telemetry? telemetry,
    SessionLog? sessionLog,
    DateTime Function()? clock,
    Future<void> Function(Duration)? sleeper,
  }) =>
      DefaultAutonomousRunner(
        agent: agent(_EchoProvider('ok'), session),
        goal: goal,
        session: session,
        policy: policy ?? const DefaultAutonomousPolicy(),
        costTracker: costTracker,
        approval: approval,
        telemetry: telemetry,
        sessionLog: sessionLog,
        clock: clock,
        sleeper: sleeper,
      );

  group('运行循环', () {
    test('无目标 → completed，0 轮', () async {
      final Session session = Session(id: 's1');
      final AutonomousResult result =
          await makeRunner(session, goals(session)).run();

      expect(result.stoppedReason, StopReason.completed);
      expect(result.turns, isEmpty);
      expect(result.totalCost, 0);
    });

    test('有目标、达到最大轮次 → maxRoundsReached，目标已推进', () async {
      final Session session = Session(id: 's1');
      final DefaultGoalService goal = goals(session);
      final Goal created = await goal.create('盯机票');

      final AutonomousResult result = await makeRunner(
        session,
        goal,
        policy: const DefaultAutonomousPolicy(maxContinuousRounds: 1),
      ).run();

      expect(result.stoppedReason, StopReason.maxRoundsReached);
      expect(result.turns, hasLength(1));
      expect(result.goalsAdvanced, <String>[created.id]);
      expect(goal.current!.round, 1);
    });

    test('预算超限 → budgetExceeded，不跑轮', () async {
      final Session session = Session(id: 's1');
      final DefaultGoalService goal = goals(session);
      await goal.create('盯机票');

      final AutonomousResult result = await makeRunner(
        session,
        goal,
        policy: const DefaultAutonomousPolicy(dailyBudget: 50),
        costTracker: _FakeCostTracker(100),
      ).run();

      expect(result.stoppedReason, StopReason.budgetExceeded);
      expect(result.turns, isEmpty);
    });

    test('手动停止：stop 后 run → manualStop，0 轮', () async {
      final Session session = Session(id: 's1');
      final DefaultGoalService goal = goals(session);
      await goal.create('盯机票');

      final DefaultAutonomousRunner runner = makeRunner(session, goal);
      runner.stop();
      final AutonomousResult result = await runner.run();

      expect(result.stoppedReason, StopReason.manualStop);
      expect(result.turns, isEmpty);
    });

    test('重复 run 抛 StateError', () async {
      final Session session = Session(id: 's1');
      final DefaultGoalService goal = goals(session);
      await goal.create('盯机票');
      final _BlockingProvider provider = _BlockingProvider();
      final DefaultAutonomousRunner runner = DefaultAutonomousRunner(
        agent:
            AgentLoop(llm: provider, tools: ToolRegistry(), session: session),
        goal: goal,
        session: session,
        policy: const DefaultAutonomousPolicy(),
      );

      final Future<AutonomousResult> pending = runner.run();
      await Future<void>.delayed(Duration.zero);
      expect(runner.run, throwsStateError);
      provider.gate.complete();
      await pending;
    });

    test('isRunning 在运行期间为 true', () async {
      final Session session = Session(id: 's1');
      final DefaultGoalService goal = goals(session);
      await goal.create('盯机票');
      final _BlockingProvider provider = _BlockingProvider();
      final DefaultAutonomousRunner runner = DefaultAutonomousRunner(
        agent:
            AgentLoop(llm: provider, tools: ToolRegistry(), session: session),
        goal: goal,
        session: session,
        policy: const DefaultAutonomousPolicy(),
      );

      final Future<AutonomousResult> pending = runner.run();
      await Future<void>.delayed(Duration.zero);
      expect(runner.isRunning, isTrue);
      provider.gate.complete();
      await pending;
      expect(runner.isRunning, isFalse);
    });
  });

  group('时间窗口', () {
    test('窗口未开始：等待到 nextStart 后继续', () async {
      final Session session = Session(id: 's1');
      final DefaultGoalService goal = goals(session);
      await goal.create('盯机票');
      DateTime now = DateTime(2026, 9, 20, 8);
      final List<Duration> slept = <Duration>[];

      final AutonomousResult result = await makeRunner(
        session,
        goal,
        policy: DefaultAutonomousPolicy(
          maxContinuousRounds: 1,
          activeWindow: TimeWindow(
            start: const Duration(hours: 9),
            end: const Duration(hours: 18),
          ),
        ),
        clock: () => now,
        sleeper: (Duration wait) async {
          slept.add(wait);
          now = now.add(wait);
        },
      ).run();

      expect(slept, <Duration>[const Duration(hours: 1)]);
      expect(result.stoppedReason, StopReason.maxRoundsReached);
      expect(result.turns, hasLength(1));
    });

    test('普通窗口已结束 → windowEnded，0 轮', () async {
      final Session session = Session(id: 's1');
      final DefaultGoalService goal = goals(session);
      await goal.create('盯机票');

      final AutonomousResult result = await makeRunner(
        session,
        goal,
        policy: DefaultAutonomousPolicy(
          activeWindow: TimeWindow(
            start: const Duration(hours: 9),
            end: const Duration(hours: 18),
          ),
        ),
        clock: () => DateTime(2026, 9, 20, 20),
      ).run();

      expect(result.stoppedReason, StopReason.windowEnded);
      expect(result.turns, isEmpty);
    });

    test('stop 中断窗口等待 → manualStop，0 轮', () async {
      final Session session = Session(id: 's1');
      final DefaultGoalService goal = goals(session);
      await goal.create('盯机票');
      final Completer<void> gate = Completer<void>();
      final DefaultAutonomousRunner runner = makeRunner(
        session,
        goal,
        policy: DefaultAutonomousPolicy(
          activeWindow: TimeWindow(
            start: const Duration(hours: 9),
            end: const Duration(hours: 18),
          ),
        ),
        clock: () => DateTime(2026, 9, 20, 8),
        sleeper: (Duration wait) => gate.future,
      );

      final Future<AutonomousResult> pending = runner.run();
      await Future<void>.delayed(Duration.zero);
      runner.stop();
      final AutonomousResult result = await pending;

      expect(result.stoppedReason, StopReason.manualStop);
      expect(result.turns, isEmpty);
    });
  });

  group('人类介入', () {
    test('requireHumanInLoop 被拒 → humanRequired，目标未推进', () async {
      final Session session = Session(id: 's1');
      final DefaultGoalService goal = goals(session);
      await goal.create('盯机票');

      final AutonomousResult result = await makeRunner(
        session,
        goal,
        policy: const DefaultAutonomousPolicy(
          requireHumanInLoop: true,
          maxContinuousRounds: 3,
        ),
        approval: AutoApproval(false),
      ).run();

      expect(result.stoppedReason, StopReason.humanRequired);
      expect(result.turns, hasLength(1));
      expect(goal.current!.round, 0);
    });

    test('requireHumanInLoop 批准 → 继续到轮次上限', () async {
      final Session session = Session(id: 's1');
      final DefaultGoalService goal = goals(session);
      await goal.create('盯机票');

      final AutonomousResult result = await makeRunner(
        session,
        goal,
        policy: const DefaultAutonomousPolicy(
          requireHumanInLoop: true,
          maxContinuousRounds: 1,
        ),
        approval: AutoApproval(true),
      ).run();

      expect(result.stoppedReason, StopReason.maxRoundsReached);
      expect(result.turns, hasLength(1));
      expect(goal.current!.round, 1);
    });

    test('策略外工具被拒 → humanRequired', () async {
      final Session session = Session(id: 's1');
      final DefaultGoalService goal = goals(session);
      await goal.create('盯机票');
      final ToolRegistry tools = ToolRegistry();
      tools.fn('rogue_tool',
          description: 'd',
          handler: (ToolContext ctx) async => ToolResult.success('ok'));
      final AgentLoop agentLoop = AgentLoop(
          llm: _ToolProvider('rogue_tool'), tools: tools, session: session);

      final DefaultAutonomousRunner runner = DefaultAutonomousRunner(
        agent: agentLoop,
        goal: goal,
        session: session,
        policy: const DefaultAutonomousPolicy(
          allowedActions: <String>{'safe_tool'},
          maxContinuousRounds: 3,
        ),
        approval: AutoApproval(false),
      );
      final AutonomousResult result = await runner.run();

      expect(result.stoppedReason, StopReason.humanRequired);
      expect(result.turns, hasLength(1));
      expect(goal.current!.round, 0);
    });

    test('策略外工具批准 → 继续推进', () async {
      final Session session = Session(id: 's1');
      final DefaultGoalService goal = goals(session);
      await goal.create('盯机票');
      final ToolRegistry tools = ToolRegistry();
      tools.fn('rogue_tool',
          description: 'd',
          handler: (ToolContext ctx) async => ToolResult.success('ok'));
      final AgentLoop agentLoop = AgentLoop(
          llm: _ToolProvider('rogue_tool'), tools: tools, session: session);

      final DefaultAutonomousRunner runner = DefaultAutonomousRunner(
        agent: agentLoop,
        goal: goal,
        session: session,
        policy: const DefaultAutonomousPolicy(
          allowedActions: <String>{'safe_tool'},
          maxContinuousRounds: 1,
        ),
        approval: AutoApproval(true),
      );
      final AutonomousResult result = await runner.run();

      expect(result.stoppedReason, StopReason.maxRoundsReached);
      expect(result.turns, hasLength(1));
      expect(goal.current!.round, 1);
    });
  });

  group('审计与埋点', () {
    test('审计日志记录 autonomous/turn 与 autonomous/finished', () async {
      final Session session = Session(id: 's1');
      final DefaultGoalService goal = goals(session);
      final Goal created = await goal.create('盯机票');
      final InMemorySessionLog log = InMemorySessionLog();

      await makeRunner(
        session,
        goal,
        policy: const DefaultAutonomousPolicy(maxContinuousRounds: 1),
        sessionLog: log,
      ).run();

      final List<SessionEvent> events = await log.read(session.id).toList();
      final SessionEvent turn =
          events.firstWhere((SessionEvent e) => e.type == 'autonomous/turn');
      final SessionEvent finished = events
          .firstWhere((SessionEvent e) => e.type == 'autonomous/finished');
      expect((turn.data as Map<String, Object?>)['goalId'], created.id);
      expect(
        (finished.data as Map<String, Object?>)['stoppedReason'],
        StopReason.maxRoundsReached.name,
      );
    });

    test('遥测发出 autonomous.round 与 autonomous.finished', () async {
      final Session session = Session(id: 's1');
      final DefaultGoalService goal = goals(session);
      await goal.create('盯机票');
      final InMemoryTelemetry telemetry = InMemoryTelemetry();

      await makeRunner(
        session,
        goal,
        policy: const DefaultAutonomousPolicy(maxContinuousRounds: 1),
        telemetry: telemetry,
      ).run();

      final List<String> names =
          telemetry.recent.map((TelemetryEvent e) => e.name).toList();
      expect(names, contains('autonomous.round'));
      expect(names, contains('autonomous.finished'));
    });
  });

  group('装配', () {
    test('provideAutonomousRunner 提供服务并装配默认策略', () {
      final Context ctx = Context.root();
      final Session session = Session(id: 's1');
      final DefaultGoalService goal = goals(session);

      final AutonomousRunner resolved = provideAutonomousRunner(
        ctx,
        agent: agent(_EchoProvider('ok'), session),
        goal: goal,
        session: session,
      );

      expect(ctx.autonomousRunner, same(resolved));
      expect(resolved.policy, isA<DefaultAutonomousPolicy>());
    });
  });
}
