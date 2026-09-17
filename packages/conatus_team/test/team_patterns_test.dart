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

LlmResult _text(String content) =>
    LlmResult(content: content, provider: 'scripted', model: 'm');

AgentTeamImpl _newTeam(LlmProvider llm) {
  final Context ctx = Context.root();
  return AgentTeamImpl(
    leadId: 'lead',
    host: ctx,
    llm: llm,
    tools: ToolRegistry(),
  );
}

void main() {
  test('SequentialPattern：链式传递，返回最后 reply', () async {
    final AgentTeamImpl team = _newTeam(
        _ScriptedProvider(<LlmResult>[_text('A'), _text('B'), _text('C')]));
    const SequentialPattern p = SequentialPattern();
    final Object? result = await p.execute(
      team: team,
      input: '起点',
      options: <String, Object?>{
        'members': <String>['a', 'b', 'c']
      },
    );
    expect(result, 'C');
    team.dispose();
  });

  test('ConcurrentPattern：并发返回 reply 列表', () async {
    final AgentTeamImpl team =
        _newTeam(_ScriptedProvider(<LlmResult>[_text('A1'), _text('B1')]));
    const ConcurrentPattern p = ConcurrentPattern();
    final Object? result = await p.execute(
      team: team,
      input: '问题',
      options: <String, Object?>{
        'members': <String>['a', 'b']
      },
    );
    expect(result, isA<List<Object?>>());
    expect(result as List<Object?>, containsAll(<String>['A1', 'B1']));
    team.dispose();
  });

  test('GroupChatPattern：轮流发言，含「完成」收敛', () async {
    final AgentTeamImpl team =
        _newTeam(_ScriptedProvider(<LlmResult>[_text('我先说'), _text('完成')]));
    const GroupChatPattern p = GroupChatPattern();
    final Object? result = await p.execute(
      team: team,
      input: '话题',
      options: <String, Object?>{
        'members': <String>['a', 'b'],
        'maxRounds': 5,
      },
    );
    expect('$result', contains('完成'));
    team.dispose();
  });

  test('MakerCheckerPattern：Checker 通过则返回提案', () async {
    final AgentTeamImpl team =
        _newTeam(_ScriptedProvider(<LlmResult>[_text('提案V1'), _text('通过认可')]));
    const MakerCheckerPattern p = MakerCheckerPattern();
    final Object? result = await p.execute(
      team: team,
      input: '需求',
      options: <String, Object?>{'maker': 'm', 'checker': 'c'},
    );
    expect(result, '提案V1');
    team.dispose();
  });

  test('MakerCheckerPattern：驳回后迭代修订（「不通过」不算通过）', () async {
    final AgentTeamImpl team = _newTeam(_ScriptedProvider(<LlmResult>[
      _text('提案V1'),
      _text('不通过：缺少缓存穿透的降级说明。'),
      _text('提案V2'),
      _text('通过：认可。'),
    ]));
    const MakerCheckerPattern p = MakerCheckerPattern();
    final Object? result = await p.execute(
      team: team,
      input: '需求',
      options: <String, Object?>{'maker': 'm', 'checker': 'c'},
    );
    expect(result, '提案V2');
    team.dispose();
  });

  test('MakerCheckerPattern：disapprove 算驳回，继续迭代', () async {
    final AgentTeamImpl team = _newTeam(_ScriptedProvider(<LlmResult>[
      _text('提案V1'),
      _text('disapprove: 缺数据支撑'),
      _text('提案V2'),
      _text('通过：认可。'),
    ]));
    const MakerCheckerPattern p = MakerCheckerPattern();
    final Object? result = await p.execute(
      team: team,
      input: '需求',
      options: <String, Object?>{'maker': 'm', 'checker': 'c'},
    );
    expect(result, '提案V2');
    team.dispose();
  });

  test('GroupChatPattern：「还没结论」不算收敛，继续轮询', () async {
    final AgentTeamImpl team = _newTeam(_ScriptedProvider(<LlmResult>[
      _text('还没结论，继续讨论'),
      _text('完成'),
    ]));
    const GroupChatPattern p = GroupChatPattern();
    final Object? result = await p.execute(
      team: team,
      input: '话题',
      options: <String, Object?>{
        'members': <String>['a', 'b'],
        'maxRounds': 5,
      },
    );
    expect('$result', contains('完成'));
    team.dispose();
  });
}
