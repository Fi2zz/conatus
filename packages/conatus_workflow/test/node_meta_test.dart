import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_team/conatus_team.dart';
import 'package:conatus_workflow/conatus_workflow.dart';
import 'package:test/test.dart';

/// 返回带宿主元数据结果的工具替身。
class _MetaTool extends Tool {
  @override
  String get name => 'meta_tool';

  @override
  String get description => '返回带宿主元数据的结果';

  @override
  Future<ToolResult> call(ToolContext context) async => ToolResult.success(
        'ok',
        value: 'ok',
        meta: <String, Object?>{'cost': 0.8, 'cache': 'hit'},
      );
}

/// 仅走工具节点，团队替身不参与。
class _NoTeam implements AgentTeam {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 轮询等待运行进入终态。
Future<void> _waitTerminal(WorkflowEngine engine, String runId) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!(engine.run(runId)?.status.isTerminal ?? false)) {
    if (DateTime.now().isAfter(deadline)) fail('等待运行终态超时');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

WorkflowEngine _engine(NodeExecutor executor) =>
    WorkflowEngineImpl(executor: executor);

void main() {
  group('节点展示元数据', () {
    test('label 与 metadata 随定义往返', () {
      const ToolNode node = ToolNode(
        id: 'report',
        dependsOn: <String>[],
        tool: 'render_report',
        label: '生成报告',
        metadata: <String, Object?>{'group': 'batch', 'cost_hint': 20},
      );
      final ToolNode back = ToolNode.fromJson(
        Map<String, Object?>.from(node.toJson()),
      );
      expect(back.label, '生成报告');
      expect(back.metadata['group'], 'batch');
      expect(back.metadata['cost_hint'], 20);
      expect(back.toJson()['label'], '生成报告');
    });

    test('未填 label / metadata 时不写入 JSON', () {
      const ToolNode node = ToolNode(
        id: 'a',
        dependsOn: <String>[],
        tool: 'noop',
      );
      expect(node.toJson().containsKey('label'), isFalse);
      expect(node.toJson().containsKey('metadata'), isFalse);
    });

    test('Agent 与子流程节点同样携带展示元数据', () {
      const AgentNode agent = AgentNode(
        id: 'write',
        dependsOn: <String>[],
        task: '整理数据',
        label: '汇总',
        metadata: <String, Object?>{'group': 'analysis'},
      );
      const SubWorkflowNode sub = SubWorkflowNode(
        id: 'sub',
        dependsOn: <String>[],
        workflow: 'summary',
        label: '汇总流程',
      );
      final AgentNode agentBack = AgentNode.fromJson(
        Map<String, Object?>.from(agent.toJson()),
      );
      final SubWorkflowNode subBack = SubWorkflowNode.fromJson(
        Map<String, Object?>.from(sub.toJson()),
      );
      expect(agentBack.label, '汇总');
      expect(agentBack.metadata['group'], 'analysis');
      expect(subBack.label, '汇总流程');
      expect(subBack.metadata, isEmpty);
    });
  });

  group('RunNode.meta', () {
    test('JSON 往返与 copyWith 保留 / 清空', () {
      const RunNode node = RunNode(
        id: 'report',
        status: RunNodeStatus.completed,
        inputs: <String, Object?>{},
        meta: <String, Object?>{'cost': 1.2},
      );
      final RunNode back = RunNode.fromJson(
        Map<String, Object?>.from(node.toJson()),
      );
      expect(back.meta['cost'], 1.2);

      expect(node.copyWith(status: RunNodeStatus.running).meta, node.meta);
      expect(node.copyWith(meta: null).meta, isEmpty);
    });
  });

  group('元数据写入运行图', () {
    test('工具节点的 ToolResult.meta 合并进 RunNode.meta', () async {
      final ToolRegistry tools = ToolRegistry()..register(_MetaTool());
      late WorkflowEngine engine;
      final NodeExecutor executor = buildNodeExecutor(
        engineOf: () => engine,
        team: _NoTeam(),
        tools: tools,
      );
      engine = _engine(executor);
      await engine.register(const WorkflowDefinition(
        name: 'meta',
        version: 1,
        outputs: <String>['report'],
        nodes: <WorkflowNode>[
          ToolNode(id: 'report', dependsOn: <String>[], tool: 'meta_tool'),
        ],
      ));
      final WorkflowRun run = await engine.start('meta');
      await _waitTerminal(engine, run.id);

      final RunNode node = engine.run(run.id)!.nodes['report']!;
      expect(node.status, RunNodeStatus.completed);
      expect(node.meta['cost'], 0.8);
      expect(node.meta['cache'], 'hit');
      engine.dispose();
    });

    test('recordNodeMeta 合并而非覆盖，未知节点静默忽略', () async {
      final WorkflowEngine engine = _engine(
        (node, run) async => 'out:${node.id}',
      );
      await engine.register(const WorkflowDefinition(
        name: 'chain',
        version: 1,
        outputs: <String>['a'],
        nodes: <WorkflowNode>[
          ToolNode(id: 'a', dependsOn: <String>[], tool: 'noop'),
        ],
      ));
      final WorkflowRun run = await engine.start('chain');
      await _waitTerminal(engine, run.id);

      await engine.recordNodeMeta(run.id, 'a', <String, Object?>{'cost': 1});
      await engine
          .recordNodeMeta(run.id, 'a', <String, Object?>{'cache': 'hit'});
      await engine.recordNodeMeta(run.id, 'missing', <String, Object?>{'x': 1});

      expect(engine.run(run.id)!.nodes['a']!.meta, <String, Object?>{
        'cost': 1,
        'cache': 'hit',
      });
      engine.dispose();
    });
  });
}
