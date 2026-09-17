import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_team/conatus_team.dart';
import 'package:test/test.dart';

class _FakeTracker implements TeamTaskTracker {
  String? begun;
  String? completed;
  String? failed;
  Object? completeResult;
  Object? failError;

  @override
  Future<String?> beginMember({
    required String teammateId,
    required String name,
    required String leadId,
  }) async {
    begun = teammateId;
    return 'task-$teammateId';
  }

  @override
  Future<void> completeMember(String teammateId, {Object? result}) async {
    completed = teammateId;
    completeResult = result;
  }

  @override
  Future<void> failMember(String teammateId, {Object? error}) async {
    failed = teammateId;
    failError = error;
  }
}

class _ThrowingTracker implements TeamTaskTracker {
  @override
  Future<String?> beginMember({
    required String teammateId,
    required String name,
    required String leadId,
  }) async =>
      throw StateError('tracker down');

  @override
  Future<void> completeMember(String teammateId, {Object? result}) async =>
      throw StateError('tracker down');

  @override
  Future<void> failMember(String teammateId, {Object? error}) async =>
      throw StateError('tracker down');
}

void main() {
  test('onSpawn 记录任务 / 会话 / 遥测；返回 tracker taskId', () async {
    final _FakeTracker tracker = _FakeTracker();
    final Session session = Session(id: 'lead');
    final InMemoryTelemetry tel = InMemoryTelemetry();
    final TeamHooks hooks = TeamHooks(
      taskTracker: tracker,
      session: session,
      telemetry: tel,
    );
    final String? taskId = await hooks.onSpawn(
      teammateId: 'm1',
      name: 'reviewer',
      leadId: 'lead',
      tools: const <String>['read'],
    );
    expect(taskId, 'task-m1');
    expect(tracker.begun, 'm1');
    expect(tel.recent.any((TelemetryEvent e) => e.name == 'team.spawn'), true);
    expect(session.ownEvents.any((SessionEvent e) => e.type == 'team/spawned'),
        true);
  });

  test('onSend 记录会话 / 遥测', () {
    final Session session = Session(id: 'lead');
    final InMemoryTelemetry tel = InMemoryTelemetry();
    final TeamHooks hooks = TeamHooks(session: session, telemetry: tel);
    hooks.onSend(from: 'lead', to: 'm1', message: '干活');
    expect(tel.recent.any((TelemetryEvent e) => e.name == 'team.send'), true);
    expect(
        session.ownEvents
            .any((SessionEvent e) => e.type == 'team/message_sent'),
        true);
  });

  test('onTaskCreated 记录会话 / 遥测', () {
    final Session session = Session(id: 'lead');
    final InMemoryTelemetry tel = InMemoryTelemetry();
    final TeamHooks hooks = TeamHooks(session: session, telemetry: tel);
    hooks.onTaskCreated(taskId: 't1', description: '审查', assigneeId: 'm1');
    expect(tel.recent.any((TelemetryEvent e) => e.name == 'team.task.create'),
        true);
    expect(
        session.ownEvents
            .any((SessionEvent e) => e.type == 'team/task_created'),
        true);
  });

  test('onRemove completed → completeMember + outcome=completed', () async {
    final _FakeTracker tracker = _FakeTracker();
    final InMemoryTelemetry tel = InMemoryTelemetry();
    final TeamHooks hooks = TeamHooks(taskTracker: tracker, telemetry: tel);
    await hooks.onRemove(teammateId: 'm1', completed: true, result: 'ok');
    expect(tracker.completed, 'm1');
    expect(tracker.completeResult, 'ok');
    expect(
        tel.recent.any((TelemetryEvent e) =>
            e.name == 'team.remove' && e.data['outcome'] == 'completed'),
        true);
  });

  test('onRemove failed → failMember + outcome=failed', () async {
    final _FakeTracker tracker = _FakeTracker();
    final InMemoryTelemetry tel = InMemoryTelemetry();
    final TeamHooks hooks = TeamHooks(taskTracker: tracker, telemetry: tel);
    await hooks.onRemove(teammateId: 'm1', completed: false, error: 'boom');
    expect(tracker.failed, 'm1');
    expect(tracker.failError, 'boom');
    expect(
        tel.recent.any((TelemetryEvent e) =>
            e.name == 'team.remove' && e.data['outcome'] == 'failed'),
        true);
  });

  test('checkSpawnApproval：null approval 放行；拒绝时 emit denied', () async {
    final TeamHooks noApproval = TeamHooks();
    expect(
        await noApproval.checkSpawnApproval(name: 'a', tools: const []), true);
    final InMemoryTelemetry tel = InMemoryTelemetry();
    final TeamHooks denied =
        TeamHooks(approval: AutoApproval(false), telemetry: tel);
    expect(await denied.checkSpawnApproval(name: 'a', tools: const []), false);
    expect(tel.recent.any((TelemetryEvent e) => e.name == 'team.spawn.denied'),
        true);
  });

  test('checkInterruptApproval：null 放行；拒绝 emit denied', () async {
    final TeamHooks noApproval = TeamHooks();
    expect(await noApproval.checkInterruptApproval(teammateId: 'm1'), true);
    final InMemoryTelemetry tel = InMemoryTelemetry();
    final TeamHooks denied =
        TeamHooks(approval: AutoApproval(false), telemetry: tel);
    expect(await denied.checkInterruptApproval(teammateId: 'm1'), false);
    expect(
        tel.recent.any((TelemetryEvent e) => e.name == 'team.interrupt.denied'),
        true);
  });

  test('seam 异常降级：session 关闭后 append 不抛', () async {
    final Session session = Session(id: 'lead')..close();
    final TeamHooks hooks = TeamHooks(session: session);
    expect(
        () => hooks.onSend(from: 'a', to: 'b', message: 'x'), returnsNormally);
  });

  test('seam 异常降级：tracker beginMember 抛错不冒泡，返回 null', () async {
    final TeamHooks hooks = TeamHooks(taskTracker: _ThrowingTracker());
    final String? taskId = await hooks.onSpawn(
      teammateId: 'm1',
      name: 'a',
      leadId: 'lead',
      tools: const <String>[],
    );
    expect(taskId, isNull);
  });

  test('seam 异常降级：tracker completeMember 抛错不冒泡', () async {
    final TeamHooks hooks = TeamHooks(taskTracker: _ThrowingTracker());
    await expectLater(
        hooks.onRemove(teammateId: 'm1', completed: true), completes);
  });
}
