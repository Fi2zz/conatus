import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_team/conatus_team.dart';
import 'package:conatus_workflow/conatus_workflow.dart';
import 'package:test/test.dart';

/// 可配置返回值的工具替身。
class FakeTool extends Tool {
  FakeTool(this.name, {this.value, this.error});

  @override
  final String name;

  final Object? value;
  final Object? error;

  @override
  String get description => 'fake $name';

  @override
  Future<ToolResult> call(ToolContext context) async {
    if (error != null) {
      return ToolResult.failure(
        '$error',
        error: ToolError('TEST_ERROR', '$error'),
      );
    }
    return ToolResult.success('$value', value: value);
  }
}

/// 记录 spawn / ask / remove 的团队替身。
class FakeAgentTeam implements AgentTeam {
  final List<Teammate> spawned = <Teammate>[];
  final List<String> asked = <String>[];
  final List<String> removed = <String>[];
  int _seq = 0;

  @override
  String get leadId => 'lead';

  @override
  Future<Teammate> spawn({
    required String name,
    List<String>? tools,
    String? systemPrompt,
  }) async {
    _seq++;
    final mate = Teammate(
      id: 'mate-$_seq',
      name: name,
      role: TeamRole.member,
      status: TeammateStatus.idle,
      tools: tools ?? const <String>[],
      createdAt: DateTime.utc(2026, 9, 17),
    );
    spawned.add(mate);
    return mate;
  }

  @override
  Future<String> ask(String teammateId, String message) async {
    asked.add(teammateId);
    return '回复-$teammateId';
  }

  @override
  Future<void> remove(String teammateId) async {
    removed.add(teammateId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 轮询等待运行进入终态。
Future<void> waitTerminal(WorkflowEngine engine, String runId) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!(engine.run(runId)?.status.isTerminal ?? false)) {
    if (DateTime.now().isAfter(deadline)) fail('等待运行终态超时');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('executor ToolNode', () {
    test('调用已注册工具并返回规范值', () async {
      final tools = ToolRegistry()..register(FakeTool('echo', value: 'hi'));
      final executor = buildNodeExecutor(
        engineOf: _noopEngine,
        team: FakeAgentTeam(),
        tools: tools,
      );
      final run = _emptyRun();
      final outputs = await executor(
        const ToolNode(id: 't', dependsOn: <String>[], tool: 'echo'),
        run,
      );
      expect(outputs, 'hi');
    });

    test('未注册工具抛 WorkflowException', () async {
      final tools = ToolRegistry();
      final executor = buildNodeExecutor(
        engineOf: _noopEngine,
        team: FakeAgentTeam(),
        tools: tools,
      );
      expect(
        () => executor(
          const ToolNode(id: 't', dependsOn: <String>[], tool: 'nope'),
          _emptyRun(),
        ),
        throwsA(
          isA<WorkflowException>().having(
            (WorkflowException e) => e.code,
            'code',
            'unknown-tool',
          ),
        ),
      );
    });

    test('工具失败抛 WorkflowException', () async {
      final tools = ToolRegistry()..register(FakeTool('bad', error: 'boom'));
      final executor = buildNodeExecutor(
        engineOf: _noopEngine,
        team: FakeAgentTeam(),
        tools: tools,
      );
      expect(
        () => executor(
          const ToolNode(id: 't', dependsOn: <String>[], tool: 'bad'),
          _emptyRun(),
        ),
        throwsA(
          isA<WorkflowException>().having(
            (WorkflowException e) => e.code,
            'code',
            'tool-failed',
          ),
        ),
      );
    });
  });

  group('executor AgentNode', () {
    test('spawn → ask → remove', () async {
      final team = FakeAgentTeam();
      final executor = buildNodeExecutor(
        engineOf: _noopEngine,
        team: team,
        tools: ToolRegistry(),
      );
      final run = _emptyRun();
      final outputs = await executor(
        const AgentNode(
          id: 'a',
          dependsOn: <String>[],
          task: '写一份报告',
          name: 'reporter',
          tools: <String>['read'],
        ),
        run,
      );
      expect(team.spawned, hasLength(1));
      expect(team.spawned.first.name, 'reporter');
      expect(team.spawned.first.tools, const <String>['read']);
      expect(team.asked, hasLength(1));
      expect(team.removed, hasLength(1));
      expect(team.removed.first, team.spawned.first.id);
      expect(outputs, '回复-${team.spawned.first.id}');
    });
  });

  group('executor SubWorkflowNode', () {
    test('递归执行子流程并返回其输出', () async {
      final tools = ToolRegistry()..register(FakeTool('echo', value: 'ok'));
      late final WorkflowEngineImpl engine;
      engine = WorkflowEngineImpl(
        executor: buildNodeExecutor(
          engineOf: () => engine,
          team: FakeAgentTeam(),
          tools: tools,
        ),
      );
      await engine.register(
        const WorkflowDefinition(
          name: 'child',
          version: 1,
          outputs: <String>['c'],
          nodes: <WorkflowNode>[
            ToolNode(id: 'c', dependsOn: <String>[], tool: 'echo'),
          ],
        ),
      );
      await engine.register(
        const WorkflowDefinition(
          name: 'parent',
          version: 1,
          outputs: <String>['s'],
          nodes: <WorkflowNode>[
            SubWorkflowNode(
              id: 's',
              dependsOn: <String>[],
              workflow: 'child',
            ),
          ],
        ),
      );

      final run = await engine.start('parent');
      await waitTerminal(engine, run.id);
      final result = engine.run(run.id)!;
      expect(result.status, RunStatus.completed);
      expect(
        result.outputs,
        const <String, Object?>{
          's': <String, Object?>{'c': 'ok'},
        },
      );
      expect(result.nodes['s']?.outputs, const <String, Object?>{'c': 'ok'});
      engine.dispose();
    });

    test('超过 maxDepth 抛 max-depth', () async {
      final tools = ToolRegistry();
      late final WorkflowEngineImpl engine;
      engine = WorkflowEngineImpl(
        executor: buildNodeExecutor(
          engineOf: () => engine,
          team: FakeAgentTeam(),
          tools: tools,
          maxDepth: 2,
        ),
      );
      // 链式子流程：p1 → p2 → p3，深度 2 触发限制。
      await engine.register(
        const WorkflowDefinition(
          name: 'p3',
          version: 1,
          nodes: <WorkflowNode>[
            ToolNode(id: 'x', dependsOn: <String>[], tool: 'noop'),
          ],
        ),
      );
      await engine.register(
        const WorkflowDefinition(
          name: 'p2',
          version: 1,
          nodes: <WorkflowNode>[
            SubWorkflowNode(id: 's', dependsOn: <String>[], workflow: 'p3'),
          ],
        ),
      );
      await engine.register(
        const WorkflowDefinition(
          name: 'p1',
          version: 1,
          nodes: <WorkflowNode>[
            SubWorkflowNode(id: 's', dependsOn: <String>[], workflow: 'p2'),
          ],
        ),
      );

      final run = await engine.start('p1');
      await waitTerminal(engine, run.id);
      final result = engine.run(run.id)!;
      expect(result.status, RunStatus.failed);
      expect(result.nodes['s']?.error, isA<WorkflowException>());
      engine.dispose();
    });
  });
}

/// 占位引擎：executor 不会真正用到。
WorkflowEngine _noopEngine() => WorkflowEngineImpl(
    executor: (WorkflowNode node, WorkflowRun run) async => null);

WorkflowRun _emptyRun() => WorkflowRun(
      id: 'r',
      workflowName: 'w',
      workflowVersion: 1,
      status: RunStatus.running,
      inputs: const <String, Object?>{},
      nodes: const <String, RunNode>{},
      createdAt: DateTime.utc(2026, 9, 17),
    );
