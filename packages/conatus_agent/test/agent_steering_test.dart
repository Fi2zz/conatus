/// Agent Loop 轮内注入缝（SteeringSource）：排队的用户插话在组下一次
/// 模型请求前注入会话，AI 轮内即可看到。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.script);

  final List<LlmResult> script;
  final List<List<LlmMessage>> calls = <List<LlmMessage>>[];

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls.add(List<LlmMessage>.of(messages));
    final int index =
        calls.length - 1 < script.length ? calls.length - 1 : script.length - 1;
    return script[index];
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

LlmResult _call(String id, String name) => LlmResult(
      content: '',
      provider: 'scripted',
      model: 'm',
      toolCalls: <LlmToolCall>[LlmToolCall(id: id, name: name)],
    );

ToolRegistry _tools() {
  final ToolRegistry tools = ToolRegistry();
  tools.fn(
    'echo',
    description: '回显',
    handler: (ToolContext ctx) async => ToolResult.success('ok'),
  );
  return tools;
}

void main() {
  group('AgentLoop — 轮内注入（SteeringSource）', () {
    test(
        '第一次请求后返回插话 → 第二次请求的 messages 含该 user 消息，'
        '会话事件里 user 消息在 tool 结果之后', () async {
      final Session session = Session(id: 's1');
      final _ScriptedProvider provider = _ScriptedProvider(<LlmResult>[
        _call('c1', 'echo'),
        _text('收到插话'),
      ]);
      final AgentLoop loop = AgentLoop(
        llm: provider,
        tools: _tools(),
        session: session,
      );
      int calls = 0;
      loop.steering = () async {
        calls += 1;
        // 第一次请求前返回空（无插话）；第二次请求前返回排队的插话。
        return calls < 2 ? const <String>[] : <String>['插话内容'];
      };

      final AgentTurn turn = await loop.run('开始干活');

      expect(turn.reply, '收到插话');
      expect(provider.calls, hasLength(2));
      final List<LlmMessage> second = provider.calls[1];
      expect(second.last.role, 'user');
      expect(second.last.content, '插话内容');
      expect(second[second.length - 2].role, 'tool');
      // 会话事件顺序：用户任务 → assistant（工具调用）→ tool 结果 → 插话 → 收口。
      expect(
        session.events.map((SessionEvent e) => e.type),
        <String>[
          kUserMessageEvent,
          kAssistantMessageEvent,
          kToolResultEvent,
          kUserMessageEvent,
          kAssistantMessageEvent,
        ],
      );
    });

    test('source 返回空 → 消息序列不变（与未挂载一致）', () async {
      final _ScriptedProvider provider = _ScriptedProvider(<LlmResult>[
        _call('c1', 'echo'),
        _text('完成'),
      ]);
      final AgentLoop loop = AgentLoop(llm: provider, tools: _tools())
        ..steering = () async => const <String>[];

      await loop.run('开始');

      final List<LlmMessage> second = provider.calls[1];
      expect(second.last.role, 'tool');
      expect(second.any((LlmMessage m) => m.content == '插话内容'), isFalse);
    });

    test('未挂载 source（null）→ 不注入', () async {
      final _ScriptedProvider provider = _ScriptedProvider(<LlmResult>[
        _call('c1', 'echo'),
        _text('完成'),
      ]);
      final AgentLoop loop = AgentLoop(llm: provider, tools: _tools());

      final AgentTurn turn = await loop.run('开始');

      expect(turn.reply, '完成');
      expect(provider.calls, hasLength(2));
      expect(provider.calls[1].last.role, 'tool');
    });

    test('一次取回多条插话 → 逐条注入，顺序保持', () async {
      final _ScriptedProvider provider = _ScriptedProvider(<LlmResult>[
        _call('c1', 'echo'),
        _text('都收到'),
      ]);
      final AgentLoop loop = AgentLoop(llm: provider, tools: _tools())
        ..steering = () async => <String>['先这句', '再这句'];

      await loop.run('开始');

      final List<LlmMessage> second = provider.calls[1];
      expect(second[second.length - 2].content, '先这句');
      expect(second.last.content, '再这句');
    });
  });
}
