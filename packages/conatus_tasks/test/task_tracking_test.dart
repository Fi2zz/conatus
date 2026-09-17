import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_schedule/conatus_schedule.dart';
import 'package:conatus_tasks/conatus_tasks.dart';
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

class _ThrowingProvider implements LlmProvider {
  @override
  String get name => 'throwing';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      Future<LlmResult>.error(StateError('模型不可用'));

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

Future<void> _waitTerminal(DefaultTaskCenter center, String id) async {
  final Stopwatch watch = Stopwatch()..start();
  while (watch.elapsed < const Duration(seconds: 2)) {
    final Task? task = center.get(id);
    if (task != null && task.isTerminal) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('任务 $id 未在 2 秒内落定');
}

void main() {
  group('TaskTracking — Agent Turn', () {
    test('一轮收口：agentTurn 任务 completed，结果带回复', () async {
      final DefaultTaskCenter center = DefaultTaskCenter();
      final TaskTracking tracking = TaskTracking(tasks: center);
      final AgentLoop loop = AgentLoop(
        llm: _ScriptedProvider(<LlmResult>[_text('你好')]),
        tools: ToolRegistry(),
      )..turnTracker = tracking;

      final AgentTurn turn = await loop.run('在吗');

      final Task task = center.all.single;
      expect(task.kind, TaskKind.agentTurn);
      expect(task.description, '处理: 在吗');
      expect(task.status, TaskStatus.completed);
      expect(task.result, turn.reply);
      expect(task.startedAt, isNotNull);
      expect(task.metadata, isEmpty, reason: '无 ctx 不关联 goal / planMode');
      expect(tracking.currentTurnTaskId, isNull);
    });

    test('一轮失败：agentTurn 任务 failed 并带错误', () async {
      final DefaultTaskCenter center = DefaultTaskCenter();
      final TaskTracking tracking = TaskTracking(tasks: center);
      final Session session = Session(id: 's1')..close();
      final AgentLoop loop = AgentLoop(
        llm: _ScriptedProvider(<LlmResult>[_text('x')]),
        tools: ToolRegistry(),
        session: session,
      )..turnTracker = tracking;

      await expectLater(loop.run('hi'), throwsStateError);

      final Task task = center.all.single;
      expect(task.status, TaskStatus.failed);
      expect(task.error, isNotNull);
    });
  });

  group('TaskTracking — spawn_agent 中间件', () {
    test('委托建 subAgent 任务，挂在当前轮次下', () async {
      final Context host = Context.root();
      addTearDown(host.dispose);
      final ToolRegistry registry = ToolRegistry();
      registry.register(SpawnAgentTool(
        host: host,
        llm: _ScriptedProvider(<LlmResult>[_text('结论：最低 720 元')]),
        tools: registry,
      ));
      final DefaultTaskCenter center = DefaultTaskCenter();
      final TaskTracking tracking = TaskTracking(tasks: center);
      registry.use(tracking.spawnAgentMiddleware);

      await tracking.beginTurn('查机票');
      final ToolResult result = await registry.call(const ToolCall(
        name: kSpawnAgentToolName,
        arguments: <String, Object?>{'task': '查明天机票', 'max_rounds': 3},
      ));
      await tracking.endTurn(result: result.content);

      expect(result.isError, isFalse);
      final Task turn =
          center.all.firstWhere((Task t) => t.kind == TaskKind.agentTurn);
      final Task sub =
          center.all.firstWhere((Task t) => t.kind == TaskKind.subAgent);
      expect(sub.parentTaskId, turn.id);
      expect(sub.description, '子 Agent: 查明天机票');
      expect(sub.metadata['maxRounds'], 3);
      expect(sub.status, TaskStatus.completed);
      expect(turn.status, TaskStatus.completed);
    });

    test('子 Agent 失败时 subAgent 任务 failed', () async {
      final Context host = Context.root();
      addTearDown(host.dispose);
      final ToolRegistry registry = ToolRegistry();
      registry.register(SpawnAgentTool(
        host: host,
        llm: _ThrowingProvider(),
        tools: registry,
      ));
      final DefaultTaskCenter center = DefaultTaskCenter();
      final TaskTracking tracking = TaskTracking(tasks: center);
      registry.use(tracking.spawnAgentMiddleware);

      final ToolResult result = await registry.call(const ToolCall(
        name: kSpawnAgentToolName,
        arguments: <String, Object?>{'task': '必失败'},
      ));

      expect(result.isError, isFalse, reason: 'spawn_agent 收敛子失败为结果');
      final Task sub =
          center.all.firstWhere((Task t) => t.kind == TaskKind.subAgent);
      expect(sub.status, TaskStatus.failed);
      expect(sub.error, contains('子 Agent 失败'));
    });
  });

  group('provideTaskTracking 装配', () {
    test('服务、工具、注入挂载与释放可逆', () async {
      final Context ctx = Context.root();
      final Session session = Session(id: 's1');
      final ToolRegistry tools = provideTools(ctx);
      final AgentLoop loop = AgentLoop(
        llm: _ScriptedProvider(<LlmResult>[_text('hi')]),
        tools: tools,
        session: session,
      );
      ctx.provide('agentLoop', loop);

      final TaskCenter center = provideTaskCenter(ctx, session: session);
      final TaskTracking tracking = provideTaskTracking(ctx);

      expect(identical(ctx.tasks, center), isTrue);
      expect(tools.get(kListTasksToolName), isNotNull);
      expect(tools.get(kCancelTasksToolName), isNotNull);
      expect(identical(loop.turnTracker, tracking), isTrue);

      await loop.run('在吗');
      expect(
        center.all
            .where((Task t) => t.kind == TaskKind.agentTurn)
            .single
            .status,
        TaskStatus.completed,
      );

      addTearDown(() {
        ctx.dispose();
        expect(loop.turnTracker, isNull, reason: '释放后钩子摘除');
        expect(ctx.has('tasks'), isFalse, reason: '服务随上下文移除');
      });
    });
  });

  group('TrackingShellExecutor', () {
    test('前台执行按退出码落定', () async {
      final DefaultTaskCenter center = DefaultTaskCenter();
      final TrackingShellExecutor executor = TrackingShellExecutor(
        inner: LocalShellExecutor(),
        tasks: center,
      );

      final ShellRunResult result = await executor.run(executor.resolve(
        const ShellExecRequest(command: 'echo hello', timeoutMs: 10000),
      ));

      expect(result.exitCode, 0);
      final Task task = center.all.single;
      expect(task.kind, TaskKind.shell);
      expect(task.description, 'Shell: echo hello');
      expect(task.status, TaskStatus.completed);
      expect(task.result, <String, Object?>{'exitCode': 0});
    });

    test('后台进程结束落定；kill 落 failed', () async {
      final DefaultTaskCenter center = DefaultTaskCenter();
      final TrackingShellExecutor executor = TrackingShellExecutor(
        inner: LocalShellExecutor(),
        tasks: center,
      );

      final ShellProcess ok = await executor.start(
          executor.resolve(const ShellExecRequest(command: 'echo async')));
      final String okId = center.all.single.id;
      await ok.done;
      await _waitTerminal(center, okId);
      expect(center.get(okId)!.status, TaskStatus.completed);

      final ShellProcess sleeper = await executor
          .start(executor.resolve(const ShellExecRequest(command: 'sleep 30')));
      final String sleepId = center.all.firstWhere((Task t) => t.id != okId).id;
      expect(sleeper.kill(), isTrue);
      await sleeper.done;
      await _waitTerminal(center, sleepId);
      expect(center.get(sleepId)!.status, TaskStatus.failed);
    });
  });

  group('trackScheduleDelivery', () {
    test('交付成功 completed，被拒 failed', () async {
      final DefaultTaskCenter center = DefaultTaskCenter();
      var calls = 0;
      final ScheduleDelivery deliver =
          trackScheduleDelivery(center, (String text) async {
        calls++;
        return calls == 1;
      });

      expect(await deliver('该喝水了'), isTrue);
      expect(await deliver('该喝水了'), isFalse);

      final List<Task> tasks =
          center.all.where((Task t) => t.kind == TaskKind.schedule).toList();
      expect(tasks.map((Task t) => t.status), <TaskStatus>[
        TaskStatus.completed,
        TaskStatus.failed,
      ]);
      expect(tasks.first.description, '提醒: 该喝水了');
    });
  });
}
