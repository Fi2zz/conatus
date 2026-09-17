import 'dart:async';

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

class _BlockingProvider implements LlmProvider {
  final Completer<LlmResult> gate = Completer<LlmResult>();

  @override
  String get name => 'blocking';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      gate.future;

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

LlmResult _text(String content) =>
    LlmResult(content: content, provider: 'scripted', model: 'm');

Matcher _throwsTeamError(String expected) => throwsA(
    isA<TeamException>().having((TeamException e) => e.code, 'code', expected));

AgentTeamImpl _newTeam(LlmProvider llm, {int maxMembers = 8}) {
  final Context ctx = Context.root();
  final ToolRegistry tools = ToolRegistry();
  return AgentTeamImpl(
    leadId: 'lead',
    host: ctx,
    llm: llm,
    tools: tools,
    maxMembers: maxMembers,
  );
}

void main() {
  group('provideAgentTeam', () {
    test('注册 team 服务并随上下文释放撤销', () {
      final Context ctx = Context.root();
      provideLlm(ctx, llm: FallbackLlm(<LlmProvider>[]));
      final Disposer d = provideAgentTeam(ctx, tools: ToolRegistry());
      expect(ctx.team, isNotNull);
      d();
      expect(() => ctx.team, throwsStateError);
      ctx.dispose();
    });
  });

  group('AgentTeamImpl — spawn / send / wait / interrupt', () {
    test('spawn 创建 idle 成员并发出 TeammateSpawned', () async {
      final AgentTeamImpl team =
          _newTeam(_ScriptedProvider(<LlmResult>[_text('ok')]));
      final List<AgentTeamEvent> events = <AgentTeamEvent>[];
      team.changes.listen(events.add);
      final Teammate m = await team.spawn(name: 'reviewer');
      expect(m.status, TeammateStatus.idle);
      expect(m.role, TeamRole.member);
      expect(m.name, 'reviewer');
      expect(team.members.length, 1);
      await Future<void>.delayed(Duration.zero);
      expect(events, anyElement(isA<TeammateSpawned>()));
      team.dispose();
    });

    test('send 触发一轮，wait 等到 reply', () async {
      final AgentTeamImpl team =
          _newTeam(_ScriptedProvider(<LlmResult>[_text('结论 A')]));
      final Teammate m = await team.spawn(name: 'a');
      await team.send(m.id, '干活');
      final Teammate done = await team.wait(m.id);
      expect(done.status, TeammateStatus.idle);
      team.dispose();
    });

    test('多次 send 串行处理', () async {
      final AgentTeamImpl team =
          _newTeam(_ScriptedProvider(<LlmResult>[_text('一'), _text('二')]));
      final Teammate m = await team.spawn(name: 'a');
      await team.send(m.id, '第一');
      await team.send(m.id, '第二');
      await team.wait(m.id);
      expect(team.members.single.status, TeammateStatus.idle);
      team.dispose();
    });

    test('interrupt 中断在途轮次，状态回 idle', () async {
      final _BlockingProvider llm = _BlockingProvider();
      final AgentTeamImpl team = _newTeam(llm);
      final Teammate m = await team.spawn(name: 'a');
      final Future<void> pending = team.send(m.id, '长任务');
      await Future<void>.delayed(Duration.zero);
      expect(team.members.single.status, TeammateStatus.working);
      await team.interrupt(m.id);
      // 中断后 gate 完成才会让本轮结束
      llm.gate.complete(_text('迟到的回复'));
      await pending;
      await team.wait(m.id);
      expect(team.members.single.status, TeammateStatus.idle);
      team.dispose();
    });

    test('waitAll 等所有成员结束', () async {
      final AgentTeamImpl team =
          _newTeam(_ScriptedProvider(<LlmResult>[_text('A1'), _text('B1')]));
      final Teammate a = await team.spawn(name: 'a');
      final Teammate b = await team.spawn(name: 'b');
      await team.send(a.id, 'xA');
      await team.send(b.id, 'xB');
      final List<Teammate> all = await team.waitAll();
      expect(all.length, 2);
      expect(all.every((Teammate t) => t.status == TeammateStatus.idle), true);
      team.dispose();
    });

    test('超过 maxMembers 抛 max-members', () async {
      final AgentTeamImpl team =
          _newTeam(_ScriptedProvider(<LlmResult>[_text('ok')]), maxMembers: 1);
      await team.spawn(name: 'a');
      await expectLater(team.spawn(name: 'b'), _throwsTeamError('max-members'));
      team.dispose();
    });

    test('send 不存在成员抛 not-found', () async {
      final AgentTeamImpl team =
          _newTeam(_ScriptedProvider(<LlmResult>[_text('ok')]));
      await expectLater(team.send('ghost', 'x'), _throwsTeamError('not-found'));
      team.dispose();
    });

    test('remove 终结成员并发出 done 状态', () async {
      final AgentTeamImpl team =
          _newTeam(_ScriptedProvider(<LlmResult>[_text('ok')]));
      final Teammate m = await team.spawn(name: 'a');
      final List<AgentTeamEvent> events = <AgentTeamEvent>[];
      team.changes.listen(events.add);
      await team.remove(m.id);
      await Future<void>.delayed(Duration.zero);
      expect(team.members, isEmpty);
      expect(events, anyElement(isA<TeammateStatusChanged>()));
      team.dispose();
    });
  });
}
