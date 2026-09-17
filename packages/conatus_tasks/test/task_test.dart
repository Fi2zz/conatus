import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_tasks/conatus_tasks.dart';
import 'package:test/test.dart';

Task _sample({TaskStatus status = TaskStatus.pending}) => Task(
      id: 't1',
      kind: TaskKind.custom,
      status: status,
      description: '查机票',
      createdAt: DateTime(2026, 9, 17, 10),
    );

void main() {
  group('Task 状态谓词', () {
    test('终态与活跃矩阵', () {
      for (final TaskStatus status in TaskStatus.values) {
        final Task task = _sample(status: status);
        expect(
            task.isTerminal,
            <TaskStatus>{
              TaskStatus.completed,
              TaskStatus.failed,
              TaskStatus.cancelled,
            }.contains(status),
            reason: status.name);
        expect(
            task.isActive,
            <TaskStatus>{
              TaskStatus.pending,
              TaskStatus.running,
              TaskStatus.paused,
            }.contains(status),
            reason: status.name);
      }
    });

    test('duration：未开始为 null，结束后为起止差', () {
      expect(_sample().duration, isNull);

      final DateTime start = DateTime(2026, 9, 17, 10);
      final Task running =
          _sample(status: TaskStatus.running).copyWith(startedAt: start);
      expect(running.duration, isNotNull);

      final Task done = running.copyWith(
        status: TaskStatus.completed,
        finishedAt: start.add(const Duration(minutes: 3)),
      );
      expect(done.duration, const Duration(minutes: 3));
    });
  });

  group('Task.copyWith', () {
    test('未传参保持原值，传 null 清除可空字段', () {
      final Task task = _sample(status: TaskStatus.running).copyWith(
        startedAt: DateTime(2026, 9, 17, 10),
        result: 'ok',
        error: 'oops',
      );

      final Task untouched = task.copyWith();
      expect(untouched.result, 'ok');
      expect(untouched.error, 'oops');
      expect(untouched.startedAt, task.startedAt);

      final Task cleared = task.copyWith(result: null, error: null);
      expect(cleared.result, isNull);
      expect(cleared.error, isNull);
      expect(task.result, 'ok', reason: '原对象不可变');
    });
  });

  group('Task JSON', () {
    test('toJson / fromJson 往返一致', () {
      final Task task = Task(
        id: 't9',
        kind: TaskKind.subAgent,
        status: TaskStatus.failed,
        description: '子 Agent: 查机票',
        createdAt: DateTime(2026, 9, 17, 10, 0, 0, 123, 456),
        startedAt: DateTime(2026, 9, 17, 10, 1),
        finishedAt: DateTime(2026, 9, 17, 10, 2),
        parentTaskId: 'parent-1',
        metadata: <String, Object?>{'goalId': 'g1', 'maxRounds': 3},
        result: <String, Object?>{'exitCode': 0},
        error: '超时',
      );

      final Task restored = Task.fromJson(task.toJson());

      expect(restored.id, task.id);
      expect(restored.kind, task.kind);
      expect(restored.status, task.status);
      expect(restored.description, task.description);
      expect(restored.createdAt, task.createdAt);
      expect(restored.startedAt, task.startedAt);
      expect(restored.finishedAt, task.finishedAt);
      expect(restored.parentTaskId, task.parentTaskId);
      expect(restored.metadata, task.metadata);
      expect(restored.result, <String, Object?>{'exitCode': 0});
      expect(restored.error, '超时');
    });

    test('宽容解析：未知枚举回退、缺日期字段不炸', () {
      final Task task = Task.fromJson(<String, Object?>{
        'id': 'x',
        'kind': 'nonsense',
        'status': 'weird',
        'description': 'd',
        'createdAt': '2026-09-17T10:00:00.000',
      });

      expect(task.kind, TaskKind.custom);
      expect(task.status, TaskStatus.pending);
      expect(task.startedAt, isNull);
      expect(task.metadata, isEmpty);
    });
  });

  group('restoreTaskState', () {
    test('按任务 id 折叠最后一个事件', () {
      final Session session = Session(id: 's1');
      final Task first = _sample();
      final Task updated = first.copyWith(status: TaskStatus.completed);
      session.append(kTaskEvent, data: first.toJson());
      session.append('goal/changed', data: <String, Object?>{'x': 1});
      session.append(kTaskEvent, data: updated.toJson());
      session.append(kTaskEvent,
          data: _sample().copyWith().toJson()..['id'] = 't2');

      final Map<String, Task> restored = restoreTaskState(session);

      expect(restored.keys, <String>['t1', 't2']);
      expect(restored['t1']!.status, TaskStatus.completed);
    });

    test('fork 不继承：只折叠会话自身后缀', () {
      final Session parent = Session(id: 'p1')
        ..append(kTaskEvent, data: _sample().toJson());
      final Session fork = parent.fork(id: 'f1');

      expect(restoreTaskState(fork), isEmpty);
      expect(restoreTaskState(parent), hasLength(1));
    });
  });
}
