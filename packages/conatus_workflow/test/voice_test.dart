import 'package:conatus_workflow/conatus_workflow.dart';
import 'package:test/test.dart';

const WorkflowDefinition kMorning = WorkflowDefinition(
  name: '晨间播报',
  version: 1,
  nodes: <WorkflowNode>[
    ToolNode(id: 'weather', dependsOn: <String>[], tool: 'weather_now'),
    ToolNode(
        id: 'schedule', dependsOn: <String>['weather'], tool: 'schedule_now'),
  ],
);

WorkflowRun runWith({
  RunStatus status = RunStatus.running,
  Map<String, RunNode> nodes = const <String, RunNode>{},
  Map<String, Object?> outputs = const <String, Object?>{},
  Object? error,
}) =>
    WorkflowRun(
      id: 'r1',
      workflowName: '晨间播报',
      workflowVersion: 1,
      status: status,
      inputs: const <String, Object?>{},
      nodes: nodes,
      outputs: outputs,
      createdAt: DateTime.utc(2026, 9, 17),
      error: error,
    );

void main() {
  test('workflowCreatedMessage 描述节点数', () {
    final message = workflowCreatedMessage(kMorning);
    expect(message, contains('「晨间播报」'));
    expect(message, contains('共 2 步'));
    expect(message, contains('要现在试一下吗？'));
  });

  test('workflowProgressMessage 反映进度', () {
    final progress = runWith(
      nodes: <String, RunNode>{
        'weather': const RunNode(
          id: 'weather',
          status: RunNodeStatus.completed,
          inputs: <String, Object?>{},
        ),
        'schedule': const RunNode(
          id: 'schedule',
          status: RunNodeStatus.pending,
          inputs: <String, Object?>{},
        ),
      },
    );
    expect(workflowProgressMessage(progress), contains('第 2 步（共 2 步）'));

    expect(
      workflowProgressMessage(
        runWith(
          nodes: <String, RunNode>{
            'weather': const RunNode(
              id: 'weather',
              status: RunNodeStatus.pending,
              inputs: <String, Object?>{},
            ),
            'schedule': const RunNode(
              id: 'schedule',
              status: RunNodeStatus.pending,
              inputs: <String, Object?>{},
            ),
          },
        ),
      ),
      contains('第 1 步（共 2 步）'),
    );
  });

  test('workflowResultMessage 汇总完成输出', () {
    final done = runWith(
      status: RunStatus.completed,
      outputs: const <String, Object?>{'weather': '晴，22 度'},
    );
    final message = workflowResultMessage(done);
    expect(message, contains('跑完了'));
    expect(message, contains('weather: 晴，22 度'));
  });

  test('workflowResultMessage 未完成与无输出', () {
    expect(workflowResultMessage(runWith()), contains('还没跑完'));
    expect(
      workflowResultMessage(runWith(status: RunStatus.completed)),
      contains('没有输出'),
    );
  });

  test('workflowFailedMessage 与 workflowUpdatedMessage', () {
    final failed = runWith(status: RunStatus.failed, error: '工具挂了');
    expect(workflowFailedMessage(failed), contains('跑失败了'));
    expect(workflowFailedMessage(failed), contains('工具挂了'));
    expect(workflowUpdatedMessage('晨间播报'), contains('按新流程跑'));
  });
}
