import 'package:conatus_workflow/conatus_workflow.dart';
import 'package:test/test.dart';

Map<String, Object?> roundTrip(RunNode node) =>
    Map<String, Object?>.from(node.toJson());

void main() {
  group('RunNode', () {
    final RunNode node = RunNode(
      id: 'weather',
      status: RunNodeStatus.completed,
      inputs: <String, Object?>{'city': '北京'},
      outputs: '晴，22 度',
      startedAt: DateTime.utc(2026, 9, 17, 1),
      finishedAt: DateTime.utc(2026, 9, 17, 1, 0, 30),
      attempts: 2,
    );

    test('toJson / fromJson 往返一致', () {
      final RunNode back = RunNode.fromJson(roundTrip(node));
      expect(back.id, node.id);
      expect(back.status, node.status);
      expect(back.inputs, node.inputs);
      expect(back.outputs, node.outputs);
      expect(back.error, node.error);
      expect(back.startedAt, node.startedAt);
      expect(back.finishedAt, node.finishedAt);
      expect(back.attempts, node.attempts);
    });

    test('duration 按开始/结束时间计算', () {
      expect(node.duration, const Duration(seconds: 30));
      expect(node.copyWith(startedAt: null).duration, isNull);
    });

    test('copyWith 传 null 清除 outputs / error，未传保持原值', () {
      final RunNode cleared = node.copyWith(outputs: null, error: 'boom');
      expect(cleared.outputs, isNull);
      expect(cleared.error, 'boom');
      expect(cleared.status, node.status);
      expect(cleared.inputs, node.inputs);

      final RunNode untouched = node.copyWith();
      expect(untouched.outputs, node.outputs);
      expect(untouched.error, node.error);
      expect(untouched.startedAt, node.startedAt);
    });

    test('fromJson 缺少 id 抛 WorkflowException', () {
      expect(
        () => RunNode.fromJson(<String, Object?>{
          'status': 'pending',
          'inputs': <String, Object?>{},
        }),
        throwsA(
          isA<WorkflowException>().having(
            (WorkflowException e) => e.code,
            'code',
            'missing-field',
          ),
        ),
      );
    });

    test('fromJson 未知枚举降级为默认值', () {
      final RunNode fallback = RunNode.fromJson(<String, Object?>{
        'id': 'x',
        'status': 'unknown',
        'inputs': <String, Object?>{},
        'attempts': 'nope',
      });
      expect(fallback.status, RunNodeStatus.pending);
      expect(fallback.attempts, 0);
      expect(fallback.startedAt, isNull);
    });
  });

  group('WorkflowRun', () {
    const RunNode done = RunNode(
      id: 'a',
      status: RunNodeStatus.completed,
      inputs: <String, Object?>{},
      outputs: 'result-a',
    );
    const RunNode ready = RunNode(
      id: 'b',
      status: RunNodeStatus.ready,
      inputs: <String, Object?>{},
    );
    final WorkflowRun run = WorkflowRun(
      id: 'run-1',
      workflowName: 'morning-brief',
      workflowVersion: 1,
      status: RunStatus.running,
      inputs: <String, Object?>{'city': '北京'},
      nodes: <String, RunNode>{'a': done, 'b': ready},
      createdAt: DateTime.utc(2026, 9, 17),
      startedAt: DateTime.utc(2026, 9, 17),
      outputs: const <String, Object?>{'a': 'result-a'},
    );

    test('toJson / fromJson 往返一致', () {
      final WorkflowRun back =
          WorkflowRun.fromJson(Map<String, Object?>.from(run.toJson()));
      expect(back.id, run.id);
      expect(back.workflowName, run.workflowName);
      expect(back.workflowVersion, run.workflowVersion);
      expect(back.status, run.status);
      expect(back.inputs, run.inputs);
      expect(back.createdAt, run.createdAt);
      expect(back.startedAt, run.startedAt);
      expect(back.outputs, run.outputs);
      expect(back.nodes.keys, run.nodes.keys);
      final RunNode nodeA = back.nodes['a']!;
      expect(nodeA.status, RunNodeStatus.completed);
      expect(nodeA.outputs, 'result-a');
    });

    test('readyNodes 只返回 ready 状态的节点', () {
      expect(run.readyNodes, const <String>['b']);
      expect(
        run.copyWith(
          nodes: <String, RunNode>{
            'a': done,
            'b': ready.copyWith(status: RunNodeStatus.running),
          },
        ).readyNodes,
        isEmpty,
      );
    });

    test('copyWith 更新状态与节点表', () {
      final WorkflowRun updated = run.copyWith(
        status: RunStatus.completed,
        finishedAt: DateTime.utc(2026, 9, 17, 2),
        error: null,
      );
      expect(updated.status, RunStatus.completed);
      expect(updated.finishedAt, DateTime.utc(2026, 9, 17, 2));
      expect(updated.error, isNull);
      expect(updated.nodes, run.nodes);
    });

    test('fromJson 缺少必填字段抛 WorkflowException', () {
      expect(
        () => WorkflowRun.fromJson(<String, Object?>{
          'workflowName': 'w',
          'workflowVersion': 1,
          'status': 'pending',
          'inputs': <String, Object?>{},
          'nodes': <String, Object?>{},
        }),
        throwsA(isA<WorkflowException>()),
      );

      expect(
        () => WorkflowRun.fromJson(<String, Object?>{
          'id': 'r',
          'workflowName': 'w',
          'workflowVersion': 1,
          'status': 'pending',
          'inputs': <String, Object?>{},
          'nodes': <String, Object?>{'bad': 'not-a-node'},
        }),
        throwsA(isA<WorkflowException>()),
      );
    });
  });
}
