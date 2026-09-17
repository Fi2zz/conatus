import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_tasks/conatus_tasks.dart';
import 'package:conatus_team/conatus_team.dart';
import 'package:conatus_workflow/conatus_workflow.dart';
import 'package:test/test.dart';

/// 记录 create / update 的任务中心替身。
class FakeTaskCenter implements TaskCenter {
  final List<Task> created = <Task>[];
  final List<String> updates = <String>[];

  @override
  Future<Task> create({
    required TaskKind kind,
    required String description,
    String? parentTaskId,
    Map<String, Object?>? metadata,
  }) async {
    final task = Task(
      id: 'task-${created.length + 1}',
      kind: kind,
      status: TaskStatus.pending,
      description: description,
      createdAt: DateTime.utc(2026, 9, 17),
      metadata: metadata ?? const <String, Object?>{},
    );
    created.add(task);
    return task;
  }

  @override
  Future<Task> update(
    String id, {
    TaskStatus? status,
    Object? result,
    Object? error,
  }) async {
    updates.add('$id:${status?.name}');
    return created.firstWhere((Task t) => t.id == id).copyWith(status: status);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 指定风险与结果的工具替身。
class RiskTool extends Tool {
  RiskTool(this.name, {this.risk = ToolRisk.low, this.value});

  @override
  final String name;

  final ToolRisk risk;

  final Object? value;

  @override
  ToolRisk get riskLevel => risk;

  @override
  String get description => 'risk $name';

  @override
  Future<ToolResult> call(ToolContext context) async =>
      ToolResult.success('$value', value: value);
}

const WorkflowDefinition kChain = WorkflowDefinition(
  name: 'chain',
  version: 1,
  outputs: <String>['b'],
  nodes: <WorkflowNode>[
    ToolNode(id: 'a', dependsOn: <String>[], tool: 't1'),
    ToolNode(id: 'b', dependsOn: <String>['a'], tool: 't2'),
  ],
);

WorkflowRun runAt(DateTime createdAt) => WorkflowRun(
      id: 'r1',
      workflowName: 'chain',
      workflowVersion: 1,
      status: RunStatus.running,
      inputs: const <String, Object?>{},
      nodes: const <String, RunNode>{},
      createdAt: createdAt,
    );

void main() {
  group('WorkflowHooks TaskCenter', () {
    test('节点启动创建 Task，完成时落定', () async {
      final taskCenter = FakeTaskCenter();
      final hooks = WorkflowHooks(taskCenter: taskCenter);
      final run = runAt(DateTime.utc(2026, 9, 17));

      await hooks.onNodeStarted(run, 'a');
      expect(taskCenter.created, hasLength(1));
      expect(taskCenter.created.first.kind, TaskKind.custom);
      expect(taskCenter.created.first.metadata, <String, Object?>{
        'runId': 'r1',
        'nodeId': 'a',
      });

      await hooks.onNodeCompleted(
        run.copyWith(
          nodes: <String, RunNode>{
            'a': const RunNode(
              id: 'a',
              status: RunNodeStatus.completed,
              inputs: <String, Object?>{},
              outputs: 'ok',
            ),
          },
        ),
        'a',
      );
      expect(taskCenter.updates, contains('task-1:completed'));

      await hooks.onNodeFailed(run, 'a', 'boom');
      expect(taskCenter.updates, contains('task-1:failed'));
    });
  });

  group('WorkflowEngine + hooks 集成', () {
    test('节点执行创建 Task，运行完成时全部落定', () async {
      final taskCenter = FakeTaskCenter();
      final tools = ToolRegistry()
        ..register(RiskTool('t1', value: 1))
        ..register(RiskTool('t2', value: 2));
      late final WorkflowEngineImpl engine;
      engine = WorkflowEngineImpl(
        executor: buildNodeExecutor(
          engineOf: () => engine,
          team: _noopTeam(),
          tools: tools,
        ),
        hooks: WorkflowHooks(taskCenter: taskCenter, tools: tools),
      );
      await engine.register(kChain);

      final run = await engine.start('chain');
      await _waitFor(run.id, engine, RunStatus.completed);

      expect(taskCenter.created, hasLength(2));
      expect(taskCenter.updates,
          containsAll(<String>['task-1:completed', 'task-2:completed']));
      engine.dispose();
    });

    test('高危节点被拒绝审批 → 节点失败', () async {
      final tools = ToolRegistry()
        ..register(RiskTool('t1', risk: ToolRisk.high, value: 1));
      late final WorkflowEngineImpl engine;
      engine = WorkflowEngineImpl(
        executor: buildNodeExecutor(
          engineOf: () => engine,
          team: _noopTeam(),
          tools: tools,
        ),
        hooks: WorkflowHooks(
          approval: AutoApproval(false),
          tools: tools,
        ),
      );
      await engine.register(
        const WorkflowDefinition(
          name: 'risky',
          version: 1,
          nodes: <WorkflowNode>[
            ToolNode(id: 'a', dependsOn: <String>[], tool: 't1'),
          ],
        ),
      );

      final run = await engine.start('risky');
      await _waitFor(run.id, engine, RunStatus.failed);

      final result = engine.run(run.id)!;
      expect(result.nodes['a']?.status, RunNodeStatus.failed);
      final error = result.nodes['a']?.error as WorkflowException;
      expect(error.code, 'approval-denied');
      engine.dispose();
    });

    test('低风险节点不触发审批', () async {
      final approval = AutoApproval(false);
      final tools = ToolRegistry()..register(RiskTool('t1', value: 1));
      late final WorkflowEngineImpl engine;
      engine = WorkflowEngineImpl(
        executor: buildNodeExecutor(
          engineOf: () => engine,
          team: _noopTeam(),
          tools: tools,
        ),
        hooks: WorkflowHooks(approval: approval, tools: tools),
      );
      await engine.register(
        const WorkflowDefinition(
          name: 'safe',
          version: 1,
          nodes: <WorkflowNode>[
            ToolNode(id: 'a', dependsOn: <String>[], tool: 't1'),
          ],
        ),
      );

      final run = await engine.start('safe');
      await _waitFor(run.id, engine, RunStatus.completed);

      expect(approval.requests, 0);
      expect(engine.run(run.id)?.nodes['a']?.status, RunNodeStatus.completed);
      engine.dispose();
    });

    test('telemetry 埋点事件齐全', () async {
      final telemetry = InMemoryTelemetry();
      final tools = ToolRegistry()
        ..register(RiskTool('t1', value: 1))
        ..register(RiskTool('t2', value: 2));
      late final WorkflowEngineImpl engine;
      engine = WorkflowEngineImpl(
        executor: buildNodeExecutor(
          engineOf: () => engine,
          team: _noopTeam(),
          tools: tools,
        ),
        hooks: WorkflowHooks(telemetry: telemetry, tools: tools),
      );
      await engine.register(kChain);

      final run = await engine.start('chain');
      await _waitFor(run.id, engine, RunStatus.completed);

      final names = telemetry.recent.map((TelemetryEvent e) => e.name).toList();
      expect(
          names,
          containsAll(<String>[
            'workflow.registered',
            'workflow.run.started',
            'workflow.node.started',
            'workflow.node.completed',
            'workflow.run.completed',
          ]));
      engine.dispose();
    });
  });

  group('Session 持久化', () {
    test('运行图快照落 Session，restoreWorkflowRun 折叠恢复', () async {
      final session = Session(id: 's');
      final hooks = WorkflowHooks(session: session);
      final run = runAt(DateTime.utc(2026, 9, 17));

      hooks.onRunStarted(run);
      hooks.onRunCompleted(run.copyWith(status: RunStatus.completed));

      final restored = restoreWorkflowRun(session);
      expect(restored, isNotNull);
      expect(restored?.id, 'r1');
      expect(restored?.status, RunStatus.completed);

      // 只折叠最后一个事件。
      expect(
        session.ownEvents
            .where((SessionEvent e) => e.type == kWorkflowRunEvent)
            .length,
        2,
      );
    });
  });
}

Future<void> _waitFor(
  String runId,
  WorkflowEngine engine,
  RunStatus status,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (engine.run(runId)?.status != status) {
    if (DateTime.now().isAfter(deadline)) fail('等待运行状态超时');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _NoopTeam implements AgentTeam {
  const _NoopTeam();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

AgentTeam _noopTeam() => const _NoopTeam();
