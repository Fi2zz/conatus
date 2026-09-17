import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_tasks/conatus_tasks.dart';
import 'package:test/test.dart';

void main() {
  group('DefaultTaskCenter 状态机', () {
    test('create 落 pending 并持久化 task/changed 事件', () async {
      final Session session = Session(id: 's1');
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      final DefaultTaskCenter center = DefaultTaskCenter(
        session: session,
        telemetry: telemetry,
      );

      final Task task = await center.create(
        kind: TaskKind.custom,
        description: '查机票',
        metadata: <String, Object?>{'goalId': 'g1'},
      );

      expect(task.status, TaskStatus.pending);
      expect(task.id, startsWith('task-'));
      expect(session.ownEvents.map((SessionEvent e) => e.type),
          <String>[kTaskEvent]);
      expect(
        (session.ownEvents.single.data! as Map)['id'],
        task.id,
      );
      expect(telemetry.recent.single.name, 'task.created');
      expect(center.get(task.id)!.description, '查机票');
      expect(center.all, hasLength(1));
      expect(center.active, hasLength(1));
    });

    test('running 自动 startedAt，completed 自动 finishedAt', () async {
      final DefaultTaskCenter center = DefaultTaskCenter();
      final Task task = await center.create(
        kind: TaskKind.custom,
        description: 'x',
      );

      final Task running =
          await center.update(task.id, status: TaskStatus.running);
      expect(running.startedAt, isNotNull);
      expect(running.status, TaskStatus.running);

      final Task done = await center.update(task.id,
          status: TaskStatus.completed, result: 'ok');
      expect(done.finishedAt, isNotNull);
      expect(done.result, 'ok');
      expect(done.isTerminal, isTrue);
    });

    test('暂停/恢复埋点 task.paused 与 task.resumed', () async {
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      final DefaultTaskCenter center = DefaultTaskCenter(telemetry: telemetry);
      final Task task = await center.create(
        kind: TaskKind.custom,
        description: 'x',
      );
      await center.update(task.id, status: TaskStatus.running);
      await center.update(task.id, status: TaskStatus.paused);
      await center.update(task.id, status: TaskStatus.running);

      expect(
        telemetry.recent.map((TelemetryEvent e) => e.name),
        <String>['task.created', 'task.started', 'task.paused', 'task.resumed'],
      );
    });

    test('终态任务不可再更新；未知任务抛 not-found', () async {
      final DefaultTaskCenter center = DefaultTaskCenter();
      final Task task = await center.create(
        kind: TaskKind.custom,
        description: 'x',
      );
      await center.update(task.id, status: TaskStatus.completed);

      await expectLater(
        center.update(task.id, status: TaskStatus.running),
        throwsA(isA<TaskException>()
            .having((TaskException e) => e.code, 'code', 'already-terminal')),
      );
      await expectLater(
        center.update('nope', status: TaskStatus.running),
        throwsA(isA<TaskException>()
            .having((TaskException e) => e.code, 'code', 'not-found')),
      );
    });

    test('changes 流广播每次变更', () async {
      final DefaultTaskCenter center = DefaultTaskCenter();
      final List<Task> emitted = <Task>[];
      center.changes.listen(emitted.add);

      final Task task = await center.create(
        kind: TaskKind.custom,
        description: 'x',
      );
      await center.update(task.id, status: TaskStatus.running);
      await center.update(task.id, status: TaskStatus.failed, error: '崩了');

      expect(emitted, hasLength(3));
      expect(emitted.last.status, TaskStatus.failed);
      expect(emitted.last.error, '崩了');
    });
  });

  group('任务树', () {
    test('childrenOf 只取直接子任务，subtreeOf 取整棵子树', () async {
      final DefaultTaskCenter center = DefaultTaskCenter();
      final Task root = await center.create(
        kind: TaskKind.agentTurn,
        description: 'root',
      );
      final Task childA = await center.create(
        kind: TaskKind.subAgent,
        description: 'a',
        parentTaskId: root.id,
      );
      final Task childB = await center.create(
        kind: TaskKind.shell,
        description: 'b',
        parentTaskId: root.id,
      );
      await center.create(
        kind: TaskKind.custom,
        description: 'a1',
        parentTaskId: childA.id,
      );

      expect(center.childrenOf(root.id), hasLength(2));
      expect(center.childrenOf(childA.id), hasLength(1));
      final List<String> subtreeIds =
          center.subtreeOf(root.id).map((Task t) => t.id).toList();
      expect(subtreeIds, hasLength(4));
      expect(
        subtreeIds,
        containsAll(<String>[root.id, childA.id, childB.id]),
      );
    });
  });

  group('cancel', () {
    test('级联取消活跃子任务并执行取消回调', () async {
      final DefaultTaskCenter center = DefaultTaskCenter();
      final Task root = await center.create(
        kind: TaskKind.agentTurn,
        description: 'root',
      );
      final Task child = await center.create(
        kind: TaskKind.subAgent,
        description: 'child',
        parentTaskId: root.id,
      );
      var cancelled = false;
      center.registerCancel(child.id, () async => cancelled = true);

      await center.cancel(root.id);

      expect(center.get(root.id)!.status, TaskStatus.cancelled);
      expect(center.get(child.id)!.status, TaskStatus.cancelled);
      expect(cancelled, isTrue, reason: '子任务取消回调应被执行');
    });

    test('shell 类任务取消走 approval，拒绝抛 cancelled', () async {
      final AutoApproval denial = AutoApproval(false);
      final DefaultTaskCenter center = DefaultTaskCenter(approval: denial);
      final Task shell = await center.create(
        kind: TaskKind.shell,
        description: 'rm -rf  build',
      );

      await expectLater(
        center.cancel(shell.id),
        throwsA(isA<TaskException>()
            .having((TaskException e) => e.code, 'code', 'cancelled')),
      );
      expect(center.get(shell.id)!.status, TaskStatus.pending);
      expect(denial.requests, 1);

      final AutoApproval grant = AutoApproval(true);
      final DefaultTaskCenter center2 = DefaultTaskCenter(approval: grant);
      final Task shell2 = await center2.create(
        kind: TaskKind.shell,
        description: 'sleep 1',
      );
      await center2.cancel(shell2.id);
      expect(center2.get(shell2.id)!.status, TaskStatus.cancelled);
      expect(grant.requests, 1);
    });

    test('非 shell 类任务不经 approval', () async {
      final AutoApproval denial = AutoApproval(false);
      final DefaultTaskCenter center = DefaultTaskCenter(approval: denial);
      final Task custom = await center.create(
        kind: TaskKind.custom,
        description: 'x',
      );

      await center.cancel(custom.id);

      expect(center.get(custom.id)!.status, TaskStatus.cancelled);
      expect(denial.requests, 0);
    });

    test('终态任务再取消抛 already-terminal', () async {
      final DefaultTaskCenter center = DefaultTaskCenter();
      final Task task = await center.create(
        kind: TaskKind.custom,
        description: 'x',
      );
      await center.update(task.id, status: TaskStatus.completed);

      await expectLater(
        center.cancel(task.id),
        throwsA(isA<TaskException>()
            .having((TaskException e) => e.code, 'code', 'already-terminal')),
      );
    });
  });

  group('restore', () {
    test('构造时自动恢复：未完成任务标记 failed', () async {
      final Session session = Session(id: 's1');
      final Task stale = Task(
        id: 'stale-1',
        kind: TaskKind.shell,
        status: TaskStatus.running,
        description: 'sleep 100',
        createdAt: DateTime(2026, 9, 17, 10),
        startedAt: DateTime(2026, 9, 17, 10),
      );
      final Task done = Task(
        id: 'done-1',
        kind: TaskKind.custom,
        status: TaskStatus.completed,
        description: 'x',
        createdAt: DateTime(2026, 9, 17, 10),
      );
      session.append(kTaskEvent, data: stale.toJson());
      session.append(kTaskEvent, data: done.toJson());

      final DefaultTaskCenter center = DefaultTaskCenter(session: session);

      final Task restored = center.get('stale-1')!;
      expect(restored.status, TaskStatus.failed);
      expect(restored.error, kTaskStaleReason);
      expect(restored.finishedAt, isNotNull);
      expect(center.get('done-1')!.status, TaskStatus.completed);
      // 失败重判定也持久化。
      expect(
        session.ownEvents.where((SessionEvent e) => e.type == kTaskEvent),
        hasLength(3),
      );
    });
  });

  group('dispose', () {
    test('幂等，释放后操作抛 disposed', () async {
      final DefaultTaskCenter center = DefaultTaskCenter();
      center.dispose();
      center.dispose();

      await expectLater(
        center.create(kind: TaskKind.custom, description: 'x'),
        throwsA(isA<TaskException>()
            .having((TaskException e) => e.code, 'code', 'disposed')),
      );
    });
  });
}
