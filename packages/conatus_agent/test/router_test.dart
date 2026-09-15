import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
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
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

class _FixedRouter implements Router {
  _FixedRouter(this.decision);

  final RouteDecision decision;
  int calls = 0;

  @override
  Future<RouteDecision> route(String input) async {
    calls++;
    return decision;
  }
}

LlmResult _text(String content) =>
    LlmResult(content: content, provider: 'scripted', model: 'm');

ToolRegistry _timeTools() {
  final ToolRegistry tools = ToolRegistry();
  tools.fn(
    'get_time',
    description: '返回当前时间',
    handler: (ToolContext ctx) async => ToolResult.success('12:00'),
  );
  return tools;
}

void main() {
  group('AgentLoop — router 快路径', () {
    test('RouteReply：本地直答，不调模型', () async {
      final _ScriptedProvider provider =
          _ScriptedProvider(<LlmResult>[_text('不应调用')]);
      final _FixedRouter router =
          _FixedRouter(const RouteDecision.reply('好的，收到。'));
      final AgentLoop loop =
          AgentLoop(llm: provider, tools: ToolRegistry(), router: router);

      final AgentTurn turn = await loop.run('你好');

      expect(turn.reply, '好的，收到。');
      expect(router.calls, 1);
      expect(provider.calls, isEmpty);
    });

    test('RoutePass：落回模型', () async {
      final _ScriptedProvider provider =
          _ScriptedProvider(<LlmResult>[_text('模型回复')]);
      final AgentLoop loop = AgentLoop(
        llm: provider,
        tools: ToolRegistry(),
        router: _FixedRouter(const RouteDecision.pass()),
      );

      final AgentTurn turn = await loop.run('随便聊聊');

      expect(turn.reply, '模型回复');
      expect(provider.calls, hasLength(1));
    });

    test('RouteTools：先执行预置工具，再交模型收口', () async {
      final Session session = Session(id: 's1');
      final _ScriptedProvider provider =
          _ScriptedProvider(<LlmResult>[_text('现在是 12:00')]);
      final AgentLoop loop = AgentLoop(
        llm: provider,
        tools: _timeTools(),
        session: session,
        router: _FixedRouter(
          const RouteDecision.tools(<LlmToolCall>[
            LlmToolCall(id: 'r1', name: 'get_time'),
          ]),
        ),
      );

      final AgentTurn turn = await loop.run('现在几点');

      expect(turn.reply, '现在是 12:00');
      expect(turn.steps, hasLength(1));
      expect(turn.steps.single.call.id, 'r1');
      expect(turn.steps.single.result.content, '12:00');
      expect(provider.calls, hasLength(1));
      expect(provider.calls.first.last.role, 'tool');
      expect(provider.calls.first.last.content, '12:00');
      expect(
        session.events.map((SessionEvent e) => e.type),
        <String>[
          kUserMessageEvent,
          kAssistantMessageEvent,
          kToolResultEvent,
          kAssistantMessageEvent,
        ],
      );
    });

    test('未装配 router：行为不变', () async {
      final _ScriptedProvider provider =
          _ScriptedProvider(<LlmResult>[_text('正常回复')]);
      final AgentLoop loop = AgentLoop(llm: provider, tools: ToolRegistry());

      expect((await loop.run('你好')).reply, '正常回复');
      expect(provider.calls, hasLength(1));
    });
  });

  group('provideAgentLoop + router', () {
    test('上下文里的 router 注入 Agent Loop', () async {
      final Context ctx = Context.root();
      final _ScriptedProvider provider =
          _ScriptedProvider(<LlmResult>[_text('不应调用')]);
      provideLlm(ctx, llm: FallbackLlm(<LlmProvider>[provider]));
      provideTools(ctx);
      provideRouter(ctx, _FixedRouter(const RouteDecision.reply('本地直答')));

      final AgentLoop loop = provideAgentLoop(ctx);

      expect((await loop.run('x')).reply, '本地直答');
      expect(provider.calls, isEmpty);
      ctx.dispose();
    });
  });
}
