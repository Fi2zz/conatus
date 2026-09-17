import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_team/conatus_team.dart';
import 'package:test/test.dart';

class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.script);
  final List<LlmResult> script;
  int calls = 0;

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    final int i = calls;
    calls++;
    return script[i < script.length ? i : script.length - 1];
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

class _CountingTracker implements TeamTaskTracker {
  int begun = 0;
  int completed = 0;
  int failed = 0;

  @override
  Future<String?> beginMember({
    required String teammateId,
    required String name,
    required String leadId,
  }) async {
    begun++;
    return 'ext-$teammateId';
  }

  @override
  Future<void> completeMember(String teammateId, {Object? result}) async {
    completed++;
  }

  @override
  Future<void> failMember(String teammateId, {Object? error}) async {
    failed++;
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

LlmResult _text(String content) =>
    LlmResult(content: content, provider: 'scripted', model: 'm');

Matcher _throwsTeamError(String code) => throwsA(
    isA<TeamException>().having((TeamException e) => e.code, 'code', code));

AgentTeamImpl _newTeamWithHooks(TeamHooks hooks, LlmProvider llm) {
  final Context ctx = Context.root();
  return AgentTeamImpl(
    leadId: 'lead',
    host: ctx,
    llm: llm,
    tools: ToolRegistry(),
    hooks: hooks,
  );
}

void main() {
  test('spawn 触发 onSpawn：tracker + telemetry + session', () async {
    final _CountingTracker tracker = _CountingTracker();
    final InMemoryTelemetry tel = InMemoryTelemetry();
    final Session session = Session(id: 'lead');
    final TeamHooks hooks = TeamHooks(
      taskTracker: tracker,
      session: session,
      telemetry: tel,
    );
    final AgentTeamImpl team =
        _newTeamWithHooks(hooks, _ScriptedProvider(<LlmResult>[_text('ok')]));
    await team.spawn(name: 'a');
    expect(tracker.begun, 1);
    expect(tel.recent.any((TelemetryEvent e) => e.name == 'team.spawn'), true);
    expect(session.ownEvents.any((SessionEvent e) => e.type == 'team/spawned'),
        true);
    team.dispose();
  });

  test('send 触发 onSend：telemetry + session', () async {
    final InMemoryTelemetry tel = InMemoryTelemetry();
    final Session session = Session(id: 'lead');
    final TeamHooks hooks = TeamHooks(session: session, telemetry: tel);
    final AgentTeamImpl team =
        _newTeamWithHooks(hooks, _ScriptedProvider(<LlmResult>[_text('r')]));
    final Teammate m = await team.spawn(name: 'a');
    await team.send(m.id, '干活');
    expect(tel.recent.any((TelemetryEvent e) => e.name == 'team.send'), true);
    expect(
        session.ownEvents
            .any((SessionEvent e) => e.type == 'team/message_sent'),
        true);
    team.dispose();
  });

  test('createTask 触发 onTaskCreated', () async {
    final InMemoryTelemetry tel = InMemoryTelemetry();
    final TeamHooks hooks = TeamHooks(telemetry: tel);
    final AgentTeamImpl team =
        _newTeamWithHooks(hooks, _ScriptedProvider(<LlmResult>[_text('x')]));
    await team.createTask(description: '任务一');
    expect(tel.recent.any((TelemetryEvent e) => e.name == 'team.task.create'),
        true);
    team.dispose();
  });

  test('remove idle 成员触发 onRemove completed', () async {
    final _CountingTracker tracker = _CountingTracker();
    final TeamHooks hooks = TeamHooks(taskTracker: tracker);
    final AgentTeamImpl team =
        _newTeamWithHooks(hooks, _ScriptedProvider(<LlmResult>[_text('x')]));
    final Teammate m = await team.spawn(name: 'a');
    await team.remove(m.id);
    expect(tracker.completed, 1);
    expect(tracker.failed, 0);
    team.dispose();
  });

  test('spawn 被 approval 拒绝抛 approval-denied', () async {
    final TeamHooks hooks = TeamHooks(approval: AutoApproval(false));
    final AgentTeamImpl team =
        _newTeamWithHooks(hooks, _ScriptedProvider(<LlmResult>[_text('x')]));
    await expectLater(
        team.spawn(name: 'a'), _throwsTeamError('approval-denied'));
    team.dispose();
  });

  test('interrupt 被 approval 拒绝抛 approval-denied', () async {
    final TeamHooks hooks = TeamHooks(
      approval: RuleBasedApproval(
        allow: (ApprovalRequest req) => req.toolName == 'spawn_teammate',
      ),
    );
    final AgentTeamImpl team =
        _newTeamWithHooks(hooks, _ScriptedProvider(<LlmResult>[_text('x')]));
    final Teammate m = await team.spawn(name: 'a');
    await expectLater(
        team.interrupt(m.id), _throwsTeamError('approval-denied'));
    team.dispose();
  });

  test('tracker 抛错时 spawn / remove 仍成功且不半注册', () async {
    final TeamHooks hooks = TeamHooks(taskTracker: _ThrowingTracker());
    final AgentTeamImpl team =
        _newTeamWithHooks(hooks, _ScriptedProvider(<LlmResult>[_text('ok')]));
    final Teammate m = await team.spawn(name: 'a');
    expect(team.members.length, 1);
    await team.remove(m.id);
    expect(team.members, isEmpty);
    team.dispose();
  });
}
