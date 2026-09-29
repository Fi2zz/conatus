/// 成员活动流：正文 / 工具轨迹经 `changes` 流出，界面据此重绘。
library;

import 'dart:async';


import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_team/conatus_team.dart';
import 'package:test/test.dart';

/// 按脚本产出结果，并在流末尾给一次 usage。
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
    final int index = calls < script.length ? calls : script.length - 1;
    calls++;
    return script[index];
  }

  // 走流式时也要把工具调用带上——AgentLoop 拿 onStream 时只认终态帧里的
  // toolCalls，终态帧不填就等于没调工具。
  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async* {
    final LlmResult result =
        await chat(messages, options: options, tools: tools);
    if (result.content.isNotEmpty) {
      yield LlmTextDelta(result.content);
    }
    yield LlmStreamDone(
      toolCalls: result.toolCalls,
      usage: const <String, dynamic>{'prompt_tokens': 10},
    );
  }

  @override
  void close() {}
}

LlmResult _text(String content) =>
    LlmResult(content: content, provider: 'scripted', model: 'm');

LlmResult _call(String name) => LlmResult(
      content: '',
      provider: 'scripted',
      model: 'm',
      toolCalls: <LlmToolCall>[LlmToolCall(id: 'c1', name: name)],
    );

ToolRegistry _tools() {
  final ToolRegistry tools = ToolRegistry();
  tools.fn(
    'get_time',
    description: '时间',
    handler: (ToolContext ctx) async => ToolResult.success('12:00'),
  );
  return tools;
}

/// 建一个挂在独立宿主上下文上的团队。
AgentTeam _team(Context host, List<LlmResult> script) => AgentTeamImpl(
      leadId: 'lead',
      host: host,
      llm: _ScriptedProvider(script),
      tools: _tools(),
    );

void main() {
  group('成员活动进 changes 流', () {
    test('起轮 → 工具调用 → 工具结果 → 正文，按序流出', () async {
      final Context host = Context.root();
      addTearDown(host.dispose);
      final List<AgentTeamEvent> events = <AgentTeamEvent>[];
      final AgentTeam team = _team(host, <LlmResult>[
        _call('get_time'),
        _text('现在 12:00'),
      ]);
      final sub = team.changes.listen(events.add);
      addTearDown(sub.cancel);

      final Teammate mate = await team.spawn(name: 'researcher');
      await team.send(mate.id, '查时间');
      await team.wait(mate.id);
      await pumpEventQueue();

      final List<TeammateActivity> acts = events
          .whereType<TeammateActed>()
          .map((TeammateActed e) => e.activity)
          .toList();
      // 一次 send = 一轮（AgentLoop 内部的多步仍算这一轮）。
      expect(acts.whereType<TeammateRoundStart>(), hasLength(1));
      expect(acts.whereType<TeammateToolCall>().single.tool, 'get_time');
      final TeammateToolResult result =
          acts.whereType<TeammateToolResult>().single;
      expect(result.tool, 'get_time');
      expect(result.failed, isFalse);
      expect(acts.whereType<TeammateText>().map((TeammateText t) => t.text).join(),
          contains('12:00'));
    });

    test('活动事件带成员 id', () async {
      final Context host = Context.root();
      addTearDown(host.dispose);
      final List<AgentTeamEvent> events = <AgentTeamEvent>[];
      final AgentTeam team = _team(host, <LlmResult>[_text('ok')]);
      final sub = team.changes.listen(events.add);
      addTearDown(sub.cancel);

      final Teammate mate = await team.spawn(name: 'w');
      await team.send(mate.id, '干活');
      await team.wait(mate.id);
      await pumpEventQueue();

      final List<TeammateActed> acted = events.whereType<TeammateActed>().toList();
      expect(acted, isNotEmpty);
      expect(acted.every((TeammateActed e) => e.teammateId == mate.id), isTrue);
    });

    test('不订阅活动时行为不变（不崩、不额外报错）', () async {
      final Context host = Context.root();
      addTearDown(host.dispose);
      final AgentTeam team = _team(host, <LlmResult>[_text('ok')]);

      final Teammate mate = await team.spawn(name: 'w');
      await team.send(mate.id, '干活');
      await team.wait(mate.id);

      // Teammate 是不可变快照，状态要看当前成员表。
      expect(team.members.single.status, TeammateStatus.finished);
    });
  });

  group('activityLine 屏上回执', () {
    test('工具调用 / 结果', () {
      expect(activityLine(const TeammateToolCall('rg')).text, '→ rg');
      expect(activityLine(const TeammateToolResult('rg')).text, startsWith('✓ rg'));
      expect(
        activityLine(const TeammateToolResult('rg', failed: true)).failed,
        isTrue,
      );
    });

    test('结果摘要取首行并截断', () {
      final TeammateActivityLine line = activityLine(
        const TeammateToolResult('rg', preview: '第一行\n第二行'),
      );
      expect(line.text, contains('第一行'));
      expect(line.text, isNot(contains('第二行')));
    });

    test('正文 / 思考截断到单行', () {
      final String long = List<String>.filled(200, '长').join();
      expect(activityLine(TeammateText(long)).text.endsWith('…'), isTrue);
      expect(activityLine(const TeammateReasoning('想')).text, '思考 想');
    });

    test('轮次行带序号', () {
      expect(activityLine(const TeammateRoundStart(3)).text, '· 第 3 轮');
    });
  });
}
