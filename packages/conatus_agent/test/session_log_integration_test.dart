import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
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
    final int index = calls < script.length ? calls : script.length - 1;
    calls++;
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

class _Setup {
  _Setup(this.ctx, this.session, this.log, this.recorder, this.loop);

  final Context ctx;
  final Session session;
  final SessionLog log;
  final SessionLogRecorder recorder;
  final AgentLoop loop;
}

/// 装配一轮「用户 → 工具调用 → 工具结果 → 收口」的完整对话。
_Setup _assemble(List<LlmResult> script, {SessionLog? withLog}) {
  final Context ctx = Context.root();
  final SessionLog log = withLog ?? InMemorySessionLog();
  provideSessionLog(ctx, log: log);
  final SessionLogRecorder recorder = provideSessionLogRecorder(ctx);
  ctx.provide('llm', _ScriptedProvider(script));
  final ToolRegistry tools = provideTools(ctx);
  tools.fn(
    'get_time',
    description: '返回当前时间',
    group: 'time',
    handler: (ToolContext _) async => ToolResult.success('12:00'),
  );
  final Session session = Session(id: 's1');
  return _Setup(
      ctx, session, log, recorder, provideAgentLoop(ctx, session: session));
}

Future<List<String>> _typesOf(SessionLog log, String sessionId) async =>
    <String>[
      await for (final SessionEvent event in log.read(sessionId)) event.type
    ];

Future<List<SessionEvent>> _eventsOf(SessionLog log, String sessionId) =>
    log.read(sessionId).toList();

void main() {
  const List<String> expectedLog = <String>[
    kUserMessageEvent,
    kLlmRequestEvent,
    kLlmResponseEvent,
    kAssistantMessageEvent,
    kToolCallEvent,
    kToolResultEvent,
    kLlmRequestEvent,
    kLlmResponseEvent,
    kAssistantMessageEvent,
  ];

  group('SessionLogRecorder — 镜像与派生', () {
    test('日志是业务会话的超集，业务会话事件序列不变', () async {
      final _Setup setup =
          _assemble(<LlmResult>[_call('c1', 'get_time'), _text('12:00')]);

      await setup.loop.run('现在几点');

      expect(
        setup.session.events.map((SessionEvent e) => e.type),
        <String>[
          kUserMessageEvent,
          kAssistantMessageEvent,
          kToolResultEvent,
          kAssistantMessageEvent,
        ],
      );
      expect(await _typesOf(setup.log, 's1'), expectedLog);
      expect(setup.log, isA<InMemorySessionLog>());
      setup.ctx.dispose();
    });

    test('模型可见即已记录：每条 llm/request 都能从日志重建', () async {
      final _Setup setup =
          _assemble(<LlmResult>[_call('c1', 'get_time'), _text('12:00')]);
      await setup.loop.run('现在几点');

      final List<SessionEvent> events = await _eventsOf(setup.log, 's1');

      expect(checkModelVisibleInvariant(events), isEmpty);
      expect(() => assertModelVisibleInvariant(events), returnsNormally);
      setup.ctx.dispose();
    });

    test('tool/call 记录 group 归因与实参', () async {
      final _Setup setup =
          _assemble(<LlmResult>[_call('c1', 'get_time'), _text('12:00')]);
      await setup.loop.run('现在几点');

      final SessionEvent call = (await _eventsOf(setup.log, 's1'))
          .singleWhere((SessionEvent e) => e.type == kToolCallEvent);
      final Map<String, Object?> data = call.data! as Map<String, Object?>;

      expect(data['name'], 'get_time');
      expect(data['callId'], 'c1');
      expect(data['group'], 'time');
      setup.ctx.dispose();
    });

    test('派生事件的 parentEventId 串成因果链', () async {
      final _Setup setup =
          _assemble(<LlmResult>[_call('c1', 'get_time'), _text('12:00')]);
      await setup.loop.run('现在几点');

      final List<SessionEvent> events = await _eventsOf(setup.log, 's1');
      for (int i = 1; i < events.length; i++) {
        expect(events[i].parentEventId, events[i - 1].id, reason: '第 $i 条事件');
      }
      expect(events.first.parentEventId, isNull);
      setup.ctx.dispose();
    });

    test('未提供 sessionLogRecorder 时不包装、业务行为不变', () async {
      final Context ctx = Context.root();
      ctx.provide('llm', _ScriptedProvider(<LlmResult>[_text('你好')]));
      provideTools(ctx);
      final Session session = Session(id: 's1');

      final AgentLoop loop = provideAgentLoop(ctx, session: session);
      await loop.run('嗨');

      expect(ctx.get<SessionLogRecorder>('sessionLogRecorder'), isNull);
      expect(
        session.events.map((SessionEvent e) => e.type),
        <String>[kUserMessageEvent, kAssistantMessageEvent],
      );
      ctx.dispose();
    });
  });

  group('SessionLogRecorder — fork 与 replay', () {
    test('在任意事件点 fork，历史是原日志的前缀', () async {
      final _Setup setup =
          _assemble(<LlmResult>[_call('c1', 'get_time'), _text('12:00')]);
      await setup.loop.run('现在几点');
      final List<SessionEvent> events = await _eventsOf(setup.log, 's1');
      final SessionEvent mark =
          events.singleWhere((SessionEvent e) => e.type == kToolResultEvent);

      final String forkId = await setup.log.fork('s1', mark.id!);

      expect(
        await _typesOf(setup.log, forkId),
        expectedLog.sublist(0, expectedLog.indexOf(kToolResultEvent) + 1),
      );
      expect(await _typesOf(setup.log, 's1'), expectedLog);
      setup.ctx.dispose();
    });

    test('replay 终态与原会话一致', () async {
      final _Setup setup =
          _assemble(<LlmResult>[_call('c1', 'get_time'), _text('12:00')]);
      await setup.loop.run('现在几点');
      final List<SessionEvent> replayed = <SessionEvent>[];
      final List<SessionEvent> direct = await _eventsOf(setup.log, 's1');

      await setup.log.replay('s1', replayed.add);

      expect(replayed.map((SessionEvent e) => e.id),
          direct.map((SessionEvent e) => e.id));
      expect(
        deriveAgentMessages(replayed)
            .map((LlmMessage m) => m.toJson())
            .toList(),
        deriveAgentMessages(setup.session.events)
            .map((LlmMessage m) => m.toJson())
            .toList(),
      );
      setup.ctx.dispose();
    });
  });

  group('provideSessionLogRecorder', () {
    test('缺 sessionLog 服务时自动补一个', () {
      final Context ctx = Context.root();

      final SessionLogRecorder recorder = provideSessionLogRecorder(ctx);

      expect(identical(ctx.sessionLog, recorder.log), isTrue);
      expect(identical(ctx.sessionLogRecorder, recorder), isTrue);
      ctx.dispose();
    });

    test('ctx.dispose 关闭日志', () {
      final Context ctx = Context.root();
      final InMemorySessionLog log = InMemorySessionLog();
      provideSessionLog(ctx, log: log);
      provideSessionLogRecorder(ctx);

      ctx.dispose();

      expect(log.closed, isTrue);
    });
  });
}
