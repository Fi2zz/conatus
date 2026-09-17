import 'dart:async';

import 'package:conatus_workflow/conatus_workflow.dart';
import 'package:test/test.dart';

/// 构造一个按节点 ID 返回输出的执行器。
NodeExecutor recordingExecutor(Object? Function(String nodeId) onCall) {
  return (WorkflowNode node, WorkflowRun run) async => onCall(node.id);
}

WorkflowDefinition chain(List<String> ids) => WorkflowDefinition(
      name: 'chain',
      version: 1,
      outputs: <String>[ids.last],
      nodes: <WorkflowNode>[
        for (final String id in ids)
          ToolNode(
            id: id,
            dependsOn: ids.takeWhile((String other) => other != id).toList(),
            tool: 'noop',
          ),
      ],
    );

void main() {
  group('WorkflowEngineImpl DAG 遍历', () {
    test('线性依赖按顺序执行，事件序列完整', () async {
      final executed = <String>[];
      final engine = WorkflowEngineImpl(
        executor: recordingExecutor(
          (String nodeId) {
            executed.add(nodeId);
            return 'out-$nodeId';
          },
        ),
      );
      await engine.register(chain(<String>['a', 'b', 'c']));

      final events = <String>[];
      engine.changes.listen((WorkflowEvent event) {
        if (event is RunNodeCompleted) events.add('done:${event.nodeId}');
        if (event is RunCompleted) events.add('completed');
      });

      final run = await engine.start('chain');
      await _waitFor(run.id, engine, RunStatus.completed);

      expect(executed, <String>['a', 'b', 'c']);
      expect(events, <String>['done:a', 'done:b', 'done:c', 'completed']);
      expect(engine.run(run.id)?.status, RunStatus.completed);
      expect(engine.run(run.id)?.outputs, <String, Object?>{'c': 'out-c'});
      engine.dispose();
    });

    test('无依赖节点并发执行，汇合后才执行下游', () async {
      var active = 0;
      var maxActive = 0;
      final callOrder = <String>[];
      final engine = WorkflowEngineImpl(
        executor: (WorkflowNode node, WorkflowRun run) async {
          active++;
          if (active > maxActive) maxActive = active;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          active--;
          callOrder.add(node.id);
          return node.id;
        },
      );
      await engine.register(
        const WorkflowDefinition(
          name: 'fan',
          version: 1,
          outputs: <String>['e'],
          nodes: <WorkflowNode>[
            ToolNode(id: 'a', dependsOn: <String>[], tool: 'noop'),
            ToolNode(id: 'b', dependsOn: <String>[], tool: 'noop'),
            ToolNode(id: 'c', dependsOn: <String>[], tool: 'noop'),
            ToolNode(
              id: 'd',
              dependsOn: <String>['a', 'b', 'c'],
              tool: 'noop',
            ),
            ToolNode(id: 'e', dependsOn: <String>['d'], tool: 'noop'),
          ],
        ),
      );

      final run = await engine.start('fan');
      await _waitFor(run.id, engine, RunStatus.completed);

      expect(maxActive, greaterThanOrEqualTo(3));
      expect(callOrder.take(3).toSet(), <String>{'a', 'b', 'c'});
      expect(callOrder.last, 'e');
      expect(engine.run(run.id)?.nodes['d']?.status, RunNodeStatus.completed);
      engine.dispose();
    });

    test('节点失败 → 运行失败，下游标记 skipped', () async {
      final engine = WorkflowEngineImpl(
        executor: recordingExecutor((String nodeId) {
          if (nodeId == 'a') throw StateError('boom');
          return 'ok';
        }),
      );
      await engine.register(chain(<String>['a', 'b', 'c']));

      final run = await engine.start('chain');
      await _waitFor(run.id, engine, RunStatus.failed);

      final result = engine.run(run.id)!;
      expect(result.status, RunStatus.failed);
      expect(result.nodes['a']?.status, RunNodeStatus.failed);
      expect(result.nodes['b']?.status, RunNodeStatus.skipped);
      expect(result.nodes['c']?.status, RunNodeStatus.skipped);
      engine.dispose();
    });

    test('start 未注册的流程抛 WorkflowException', () async {
      final engine = WorkflowEngineImpl(
        executor: recordingExecutor((String nodeId) => null),
      );
      expect(
        () => engine.start('missing'),
        throwsA(isA<WorkflowException>()),
      );
      engine.dispose();
    });
  });

  group('WorkflowEngineImpl 运行时控制', () {
    test('pause 在当前节点完成后暂停，resume 继续', () async {
      final pending = <String, Completer<Object?>>{};
      final engine = WorkflowEngineImpl(
        executor: (WorkflowNode node, WorkflowRun run) {
          if (node.id == 'a') {
            final completer = Completer<Object?>();
            pending[node.id] = completer;
            return completer.future;
          }
          return Future<Object?>.value('done-${node.id}');
        },
      );
      await engine.register(chain(<String>['a', 'b']));

      final run = await engine.start('chain');
      await _until(() => pending.containsKey('a'));

      await engine.pause(run.id);
      pending['a']!.complete('done-a');
      await _until(
        () => engine.run(run.id)?.status == RunStatus.paused,
      );
      expect(engine.run(run.id)?.nodes['b']?.status, RunNodeStatus.pending);

      await engine.resume(run.id);
      await _waitFor(run.id, engine, RunStatus.completed);
      expect(engine.run(run.id)?.nodes['b']?.status, RunNodeStatus.completed);
      engine.dispose();
    });

    test('cancel 中止未完成节点，运行置 cancelled', () async {
      final pending = <String, Completer<Object?>>{};
      final engine = WorkflowEngineImpl(
        executor: (WorkflowNode node, WorkflowRun run) {
          final completer = Completer<Object?>();
          pending[node.id] = completer;
          return completer.future;
        },
      );
      await engine.register(chain(<String>['a', 'b']));

      final run = await engine.start('chain');
      await _until(() => pending.containsKey('a'));

      await engine.cancel(run.id);
      pending['a']!.complete('done-a');
      await _waitFor(run.id, engine, RunStatus.cancelled);

      final result = engine.run(run.id)!;
      expect(result.status, RunStatus.cancelled);
      expect(result.nodes['b']?.status, RunNodeStatus.pending);
      engine.dispose();
    });

    test('rerun 级联重置下游并重新执行', () async {
      var aCalls = 0;
      late final WorkflowEngineImpl engine;
      engine = WorkflowEngineImpl(
        executor: recordingExecutor((String nodeId) {
          if (nodeId == 'a') {
            aCalls++;
            return 'a-$aCalls';
          }
          final aOutput = engine.run('rerun-run')?.nodes['a']?.outputs;
          return 'b($aOutput)';
        }),
      );
      await engine.register(chain(<String>['a', 'b']));

      final run = await engine.start('chain', runId: 'rerun-run');
      await _waitFor(run.id, engine, RunStatus.completed);
      expect(engine.run(run.id)?.nodes['b']?.outputs, 'b(a-1)');

      await engine.rerun(run.id, 'a');
      await _waitFor(run.id, engine, RunStatus.completed);

      expect(aCalls, 2);
      expect(engine.run(run.id)?.nodes['a']?.outputs, 'a-2');
      expect(engine.run(run.id)?.nodes['b']?.outputs, 'b(a-2)');
      engine.dispose();
    });
  });
}

/// 轮询等待运行进入指定状态。
Future<void> _waitFor(
  String runId,
  WorkflowEngine engine,
  RunStatus status,
) async {
  await _until(() => engine.run(runId)?.status == status);
}

/// 轮询直到条件满足或超时。
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待条件超时');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
