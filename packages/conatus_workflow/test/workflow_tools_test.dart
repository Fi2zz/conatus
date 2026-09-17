import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_workflow/conatus_workflow.dart';
import 'package:test/test.dart';

WorkflowEngine newEngine() => WorkflowEngineImpl(
      executor: (WorkflowNode node, WorkflowRun run) async => 'out',
    );

const WorkflowDefinition kDef = WorkflowDefinition(
  name: 'w',
  version: 1,
  outputs: <String>['a'],
  nodes: <WorkflowNode>[
    ToolNode(id: 'a', dependsOn: <String>[], tool: 'noop'),
  ],
);

void main() {
  group('workflow_create', () {
    test('注册成功返回流程名', () async {
      final engine = newEngine();
      final tool = WorkflowCreateTool(engine);
      final result = await tool.call(ToolContext(
        ToolCall(
          name: 'workflow_create',
          arguments: <String, Object?>{'definition': kDef.toJson()},
        ),
      ));
      expect(result.isError, isFalse);
      expect(result.content, contains('已注册流程「w」'));
      expect(engine.definition('w'), isNotNull);
      engine.dispose();
    });

    test('非法定义返回失败而非抛出', () async {
      final engine = newEngine();
      final tool = WorkflowCreateTool(engine);
      final result = await tool.call(const ToolContext(
        ToolCall(
          name: 'workflow_create',
          arguments: <String, Object?>{
            'definition': <String, Object?>{
              'name': 'w',
            }
          },
        ),
      ));
      expect(result.isError, isTrue);
      expect(result.error?.code, 'missing-field');
      engine.dispose();
    });
  });

  group('workflow_run / workflow_status / workflow_list', () {
    test('启动返回 run_id，状态查询反映进度', () async {
      final engine = newEngine();
      await engine.register(kDef);
      final runTool = WorkflowRunTool(engine);
      final runResult = await runTool.call(const ToolContext(
        ToolCall(
          name: 'workflow_run',
          arguments: <String, Object?>{'name': 'w'},
        ),
      ));
      expect(runResult.isError, isFalse);
      final runId = runResult.value as String;

      await _waitFor(runId, engine, RunStatus.completed);
      final statusTool = WorkflowStatusTool(engine);
      final statusResult = await statusTool.call(ToolContext(
        ToolCall(
          name: 'workflow_status',
          arguments: <String, Object?>{'run_id': runId},
        ),
      ));
      expect(statusResult.isError, isFalse);
      expect(statusResult.content, contains('completed（1/1）'));
      engine.dispose();
    });

    test('status 未知运行返回失败', () async {
      final engine = newEngine();
      final tool = WorkflowStatusTool(engine);
      final result = await tool.call(const ToolContext(
        ToolCall(
          name: 'workflow_status',
          arguments: <String, Object?>{'run_id': 'ghost'},
        ),
      ));
      expect(result.isError, isTrue);
      engine.dispose();
    });

    test('list 汇总流程与运行', () async {
      final engine = newEngine();
      await engine.register(kDef);
      final tool = WorkflowListTool(engine);
      final result = await tool.call(const ToolContext(
        ToolCall(name: 'workflow_list'),
      ));
      expect(result.content, contains('流程: w'));
      engine.dispose();
    });

    test('run 未注册流程返回失败', () async {
      final engine = newEngine();
      final tool = WorkflowRunTool(engine);
      final result = await tool.call(const ToolContext(
        ToolCall(
          name: 'workflow_run',
          arguments: <String, Object?>{'name': 'ghost'},
        ),
      ));
      expect(result.isError, isTrue);
      expect(result.error?.code, 'unknown-workflow');
      engine.dispose();
    });
  });

  group('workflow_pause / resume / cancel / rerun', () {
    test('pause 与 resume 往返', () async {
      final engine = newEngine();
      await engine.register(kDef);
      final run = await engine.start('w');

      final pause = await WorkflowPauseTool(engine).call(ToolContext(
        ToolCall(
          name: 'workflow_pause',
          arguments: <String, Object?>{'run_id': run.id},
        ),
      ));
      expect(pause.isError, isFalse);
      await _waitFor(run.id, engine, RunStatus.paused);

      final resume = await WorkflowResumeTool(engine).call(ToolContext(
        ToolCall(
          name: 'workflow_resume',
          arguments: <String, Object?>{'run_id': run.id},
        ),
      ));
      expect(resume.isError, isFalse);
      await _waitFor(run.id, engine, RunStatus.completed);
      engine.dispose();
    });

    test('rerun 重跑节点', () async {
      final engine = newEngine();
      await engine.register(kDef);
      final run = await engine.start('w');
      await _waitFor(run.id, engine, RunStatus.completed);

      final rerun = await WorkflowRerunTool(engine).call(ToolContext(
        ToolCall(
          name: 'workflow_rerun',
          arguments: <String, Object?>{'run_id': run.id, 'node_id': 'a'},
        ),
      ));
      expect(rerun.isError, isFalse);
      await _waitFor(run.id, engine, RunStatus.completed);
      engine.dispose();
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
