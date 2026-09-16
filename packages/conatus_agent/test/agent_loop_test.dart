import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_compaction/conatus_compaction.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.script);

  final List<LlmResult> script;
  final List<List<LlmMessage>> calls = <List<LlmMessage>>[];
  List<Map<String, dynamic>>? lastTools;

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls.add(List<LlmMessage>.of(messages));
    lastTools = tools;
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

LlmResult _call(String id, String name, [String args = '{}']) => LlmResult(
      content: '',
      provider: 'scripted',
      model: 'm',
      toolCalls: <LlmToolCall>[
        LlmToolCall(id: id, name: name, arguments: args)
      ],
    );

ToolRegistry _timeTools({bool failing = false}) {
  final ToolRegistry tools = ToolRegistry();
  tools.fn(
    'get_time',
    description: '返回当前时间',
    handler: (ToolContext ctx) async => failing
        ? ToolResult.failure('时钟坏了', error: const ToolError('CLOCK', 'broken'))
        : ToolResult.success('12:00'),
  );
  return tools;
}

void main() {
  group('AgentLoop — 收口', () {
    test('纯文本回复：单步、无工具、schema 已下发', () async {
      final _ScriptedProvider provider =
          _ScriptedProvider(<LlmResult>[_text('你好')]);
      final ToolRegistry tools = _timeTools();
      final AgentLoop loop = AgentLoop(llm: provider, tools: tools);

      final AgentTurn turn = await loop.run('在吗');

      expect(turn.reply, '你好');
      expect(turn.steps, isEmpty);
      expect(provider.calls, hasLength(1));
      expect(provider.lastTools, isNotNull);
      expect(provider.lastTools!.single['name'], 'get_time');
    });

    test('工具调用闭环：执行工具并回填后收口', () async {
      final _ScriptedProvider provider = _ScriptedProvider(<LlmResult>[
        _call('c1', 'get_time'),
        _text('现在是 12:00'),
      ]);
      final AgentLoop loop = AgentLoop(llm: provider, tools: _timeTools());

      final AgentTurn turn = await loop.run('现在几点');

      expect(turn.reply, '现在是 12:00');
      expect(turn.steps, hasLength(1));
      expect(turn.steps.single.call.name, 'get_time');
      expect(turn.steps.single.result.content, '12:00');
      // 第二轮上下文里带配对的 assistant tool_calls 与 tool 结果。
      final List<LlmMessage> second = provider.calls[1];
      expect(second[second.length - 2].toolCalls.single.id, 'c1');
      expect(second.last.role, 'tool');
      expect(second.last.toolCallId, 'c1');
      expect(second.last.content, '12:00');
    });

    test('工具失败作为结果回填，不中断循环', () async {
      final _ScriptedProvider provider = _ScriptedProvider(<LlmResult>[
        _call('c1', 'get_time'),
        _text('时钟暂时不可用'),
      ]);
      final AgentLoop loop =
          AgentLoop(llm: provider, tools: _timeTools(failing: true));

      final AgentTurn turn = await loop.run('现在几点');

      expect(turn.steps.single.result.isError, isTrue);
      expect(turn.reply, '时钟暂时不可用');
      expect(provider.calls, hasLength(2));
    });
  });

  group('AgentLoop — 会话', () {
    test('事件落盘并可由 deriveAgentMessages 还原', () async {
      final Session session = Session(id: 's1');
      final _ScriptedProvider provider = _ScriptedProvider(<LlmResult>[
        _call('c1', 'get_time'),
        _text('12:00'),
      ]);
      final AgentLoop loop = AgentLoop(
        llm: provider,
        tools: _timeTools(),
        session: session,
      );

      await loop.run('现在几点');

      expect(
        session.events.map((SessionEvent e) => e.type),
        <String>[
          kUserMessageEvent,
          kAssistantMessageEvent,
          kToolResultEvent,
          kAssistantMessageEvent,
        ],
      );
      final List<LlmMessage> restored = deriveAgentMessages(session.events);
      expect(restored, hasLength(4));
      expect(restored[0].role, 'user');
      expect(restored[1].toolCalls.single.id, 'c1');
      expect(restored[2].toolCallId, 'c1');
      expect(restored[3].content, '12:00');
    });

    test('会话在循环中被关闭则中止', () async {
      final Session session = Session(id: 's1')..close();
      final AgentLoop loop = AgentLoop(
        llm: _ScriptedProvider(<LlmResult>[_text('x')]),
        tools: ToolRegistry(),
        session: session,
      );

      await expectLater(loop.run('hi'), throwsStateError);
    });
  });

  group('AgentLoop — 上下文与记忆', () {
    test('systemPrompt 装配进 system 消息', () async {
      final SystemPrompt prompt = SystemPrompt()
        ..section(PromptSection(name: 'persona', text: () => '你是助手。'));
      final _ScriptedProvider provider =
          _ScriptedProvider(<LlmResult>[_text('好的')]);
      final AgentLoop loop = AgentLoop(
        llm: provider,
        tools: ToolRegistry(),
        systemPrompt: prompt,
      );

      await loop.run('你好');

      expect(provider.calls.first.first.role, 'system');
      expect(provider.calls.first.first.content, contains('你是助手。'));
    });

    test('动态上下文拼进 system，未注册时逐字不变', () async {
      final SystemPrompt prompt = SystemPrompt()
        ..section(PromptSection(name: 'persona', text: () => '你是助手。'));
      final _ScriptedProvider provider =
          _ScriptedProvider(<LlmResult>[_text('好的'), _text('好的')]);
      final AgentLoop loop = AgentLoop(
        llm: provider,
        tools: ToolRegistry(),
        systemPrompt: prompt,
      );

      await loop.run('你好');
      expect(provider.calls.first.first.content, '你是助手。');

      prompt.context(PromptContext(
          name: 'time', order: -10, text: () => '[当前时间]\n2026-09-16 周三'));
      await loop.run('今天几号');

      expect(
        provider.calls.last.first.content,
        '你是助手。\n\n[当前时间]\n2026-09-16 周三',
      );
    });

    test('运行时调整 persona：闭包 text 在下一轮生效', () async {
      String persona = '你是助手。';
      final SystemPrompt prompt = SystemPrompt()
        ..section(PromptSection(name: 'persona', text: () => persona));
      final _ScriptedProvider provider = _ScriptedProvider(
        <LlmResult>[_text('好的'), _text('好的')],
      );
      final AgentLoop loop = AgentLoop(
        llm: provider,
        tools: ToolRegistry(),
        systemPrompt: prompt,
      );

      await loop.run('你好');
      persona = '你是翻译。';
      await loop.run('再见');

      expect(provider.calls.first.first.content, contains('你是助手。'));
      expect(provider.calls.last.first.content, contains('你是翻译。'));
    });

    test('长期记忆召回进 system，回复记入记忆', () async {
      final MemoryStore memory = MemoryStore();
      await memory.remember('用户喜欢京剧', tags: <String>{'偏好'});
      final _ScriptedProvider provider =
          _ScriptedProvider(<LlmResult>[_text('好的')]);
      final AgentLoop loop = AgentLoop(
        llm: provider,
        tools: ToolRegistry(),
        memory: memory,
      );

      await loop.run('给我讲讲京剧');

      expect(provider.calls.first.first.content, contains('用户喜欢京剧'));
      expect(memory.length, 2);
      expect(memory.entries.last.tags, contains('conversation'));
    });

    test('压缩：超预算时产出摘要并窗口化历史', () async {
      final Session session = Session(id: 's1');
      for (int i = 0; i < 4; i++) {
        session
            .append(kUserMessageEvent, data: <String, Object?>{'text': '第$i条'});
      }
      final Compactor compactor = Compactor(keepRecent: 1);
      final _ScriptedProvider provider = _ScriptedProvider(<LlmResult>[
        _text('这是摘要'),
        _text('最终回复'),
      ]);
      final AgentLoop loop = AgentLoop(
        llm: provider,
        tools: ToolRegistry(),
        session: session,
        compactor: compactor,
      );

      final AgentTurn turn = await loop.run('新问题');

      expect(compactor.summaryOf('s1'), '这是摘要');
      expect(provider.calls, hasLength(2));
      expect(provider.calls.last.first.content, contains('[历史摘要]'));
      expect(provider.calls.last.first.content, contains('这是摘要'));
      expect(session.events.map((SessionEvent e) => e.type), <String>[
        kUserMessageEvent,
        kUserMessageEvent,
        kUserMessageEvent,
        kUserMessageEvent,
        kUserMessageEvent,
        kCompactionStartEvent,
        kCompactionSummaryEvent,
        kCompactionEndEvent,
        kAssistantMessageEvent,
      ]);
      expect(checkCompactionInvariant(session.events), isEmpty);
      expect(turn.reply, '最终回复');
    });
  });

  group('provideAgentLoop', () {
    test('依赖 llm + tools，作为 agentLoop 服务提供', () async {
      final Context ctx = Context.root();
      provideLlm(ctx,
          llm: FallbackLlm(<LlmProvider>[
            _ScriptedProvider(<LlmResult>[_text('hi')]),
          ]));
      provideTools(ctx);

      final AgentLoop loop = provideAgentLoop(ctx, maxSteps: 3);

      expect(identical(ctx.agentLoop, loop), isTrue);
      expect((await loop.run('x')).reply, 'hi');
      ctx.dispose();
    });
  });
}
