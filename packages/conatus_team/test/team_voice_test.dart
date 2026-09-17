import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_team/conatus_team.dart';
import 'package:test/test.dart';

LlmResult _text(String content) =>
    LlmResult(content: content, provider: 'scripted', model: 'm');

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

void main() {
  test('teamCreatedMessage：N 个助手播报', () {
    final String msg = teamCreatedMessage(<Teammate>[
      Teammate(
          id: '1',
          name: '性能',
          role: TeamRole.member,
          status: TeammateStatus.idle,
          tools: const <String>[],
          createdAt: DateTime.now()),
      Teammate(
          id: '2',
          name: '安全',
          role: TeamRole.member,
          status: TeammateStatus.idle,
          tools: const <String>[],
          createdAt: DateTime.now()),
    ]);
    expect(msg, contains('2 个助手'));
    expect(msg, contains('性能'));
    expect(msg, contains('安全'));
  });

  test('progressMessage：按状态播报', () async {
    final Context ctx = Context.root();
    final AgentTeamImpl team = AgentTeamImpl(
      leadId: 'lead',
      host: ctx,
      llm: _ScriptedProvider(<LlmResult>[_text('ok')]),
      tools: ToolRegistry(),
    );
    addTearDown(ctx.dispose);
    await team.spawn(name: 'A');
    await team.spawn(name: 'B');
    final String msg = progressMessage(team);
    expect(msg, contains('A 还没开始'));
    expect(msg, contains('B 还没开始'));
  });

  test('progressMessage：finished 成员播报「已完成」', () async {
    final Context ctx = Context.root();
    final AgentTeamImpl team = AgentTeamImpl(
      leadId: 'lead',
      host: ctx,
      llm: _ScriptedProvider(<LlmResult>[_text('ok')]),
      tools: ToolRegistry(),
    );
    addTearDown(ctx.dispose);
    final Teammate m = await team.spawn(name: 'A');
    await team.send(m.id, '干活');
    await team.wait(m.id);
    expect(team.members.single.status, TeammateStatus.finished);
    expect(progressMessage(team), contains('A 已完成'));
  });

  test('resultMessage：汇总播报', () {
    final String msg = resultMessage(<String, String>{
      '性能': 'OK',
      '安全': '有问题',
    });
    expect(msg, contains('2 个助手'));
    expect(msg, contains('性能：OK'));
    expect(msg, contains('安全：有问题'));
    expect(msg, contains('需要我详细说说'));
  });

  test('memberRemovedMessage：移除播报', () {
    final String msg = memberRemovedMessage('产品');
    expect(msg, contains('产品'));
    expect(msg, contains('已经停了'));
  });

  test('TeamVoice.noop 不抛', () {
    expect(() => TeamVoice.noop.say('hello'), returnsNormally);
  });
}
