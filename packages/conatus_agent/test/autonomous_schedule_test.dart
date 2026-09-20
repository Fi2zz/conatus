import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_schedule/conatus_schedule.dart';
import 'package:test/test.dart';

/// 记录调用、可注入失败的假 Runner。
class _FakeRunner implements AutonomousRunner {
  int runs = 0;
  bool running = false;
  bool fail = false;

  @override
  Future<AutonomousResult> run() async {
    runs++;
    if (fail) throw StateError('boom');
    return const AutonomousResult(
      turns: <AgentTurn>[],
      goalsAdvanced: <String>[],
      totalCost: 0,
      stoppedReason: StopReason.completed,
    );
  }

  @override
  void stop() {}

  @override
  bool get isRunning => running;

  @override
  void setPolicy(AutonomousPolicy policy) {}

  @override
  AutonomousPolicy get policy => const DefaultAutonomousPolicy();
}

/// 固定文本回复的假模型。
class _EchoProvider implements LlmProvider {
  @override
  String get name => 'echo';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async =>
      LlmResult(content: 'ok', provider: name, model: 'm');

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
  group('autonomousDelivery', () {
    test('空闲时触发一轮并返回 true；运行中返回 false 不触发', () async {
      final _FakeRunner runner = _FakeRunner();
      final ScheduleDelivery deliver = autonomousDelivery(runner);

      expect(await deliver('到点了'), isTrue);
      expect(runner.runs, 1);

      runner.running = true;
      expect(await deliver('到点了'), isFalse);
      expect(runner.runs, 1);
    });

    test('单轮失败经 onError 上报，不抛给调度', () async {
      final _FakeRunner runner = _FakeRunner()..fail = true;
      final List<Object> errors = <Object>[];
      final ScheduleDelivery deliver =
          autonomousDelivery(runner, onError: errors.add);

      await deliver('到点了');
      await Future<void>.delayed(Duration.zero);

      expect(runner.runs, 1);
      expect(errors, hasLength(1));
    });
  });

  group('provideAutonomousSchedule', () {
    test('到期提醒触发一轮自主运营', () async {
      final Session session = Session(id: 's1');
      addTearDown(session.close);
      final DefaultGoalService goal = DefaultGoalService(session: session);
      await goal.create('盯机票');
      final AgentLoop agent = AgentLoop(
          llm: _EchoProvider(), tools: ToolRegistry(), session: session);
      final Context ctx = Context.root();
      provideSessionSchedule(ctx, session: session);
      provideAutonomousRunner(
        ctx,
        agent: agent,
        goal: goal,
        session: session,
        policy: const DefaultAutonomousPolicy(maxContinuousRounds: 1),
      );
      provideAutonomousSchedule(ctx, runner: ctx.autonomousRunner);

      final SessionSchedule schedule = ctx.schedule;
      final DateTime due =
          DateTime.now().toUtc().add(const Duration(milliseconds: 60));
      await schedule.create(at: formatUtcInstant(due), prompt: '跑一轮');
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(goal.current!.round, 1, reason: '到期提醒应触发一轮自主运营');
      ctx.dispose();
    });
  });
}
