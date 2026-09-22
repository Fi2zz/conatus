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

void main() {
  group('InMemoryTelemetry', () {
    test('emit 记录并广播；limit 截断', () async {
      final InMemoryTelemetry telemetry = InMemoryTelemetry(limit: 2);
      final List<TelemetryEvent> streamed = <TelemetryEvent>[];
      final subscription = telemetry.events.listen(streamed.add);

      telemetry.emit(TelemetryEvent('a'));
      telemetry.emit(TelemetryEvent('b'));
      telemetry.emit(TelemetryEvent('c'));
      await Future<void>.delayed(Duration.zero);

      expect(telemetry.recent.map((TelemetryEvent e) => e.name),
          <String>['b', 'c']);
      expect(
          streamed.map((TelemetryEvent e) => e.name), <String>['a', 'b', 'c']);
      await subscription.cancel();
      await telemetry.close();
    });

    test('limit 为负抛 ArgumentError', () {
      expect(() => InMemoryTelemetry(limit: -1), throwsArgumentError);
    });
  });

  test('ConsoleTelemetry 写行，events 为空', () {
    final List<String> lines = <String>[];
    final ConsoleTelemetry telemetry = ConsoleTelemetry(writer: lines.add);

    telemetry.emit(
        TelemetryEvent('tool.called', data: <String, Object?>{'tool': 'x'}));

    expect(lines.single, contains('tool.called'));
    expect(lines.single, contains('"tool":"x"'));
    expect(telemetry.events, emitsDone);
  });

  group('instrumentTools', () {
    test('工具调用后发 tool.called', () async {
      final Context ctx = Context.root();
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      provideTelemetry(ctx, telemetry: telemetry);
      final ToolRegistry tools = provideTools(ctx);
      tools.fn('echo',
          handler: (ToolContext c) async => ToolResult.success('ok'));
      instrumentTools(ctx, telemetry: telemetry);

      await tools.call(const ToolCall(name: 'echo'));

      final TelemetryEvent event = telemetry.recent.last;
      expect(event.name, 'tool.called');
      expect(event.data['tool'], 'echo');
      expect(event.data['isError'], isFalse);
      ctx.dispose();
    });

    test('工具返回 ToolResult.failure → 发 tool.failed', () async {
      final Context ctx = Context.root();
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      provideTelemetry(ctx, telemetry: telemetry);
      final ToolRegistry tools = provideTools(ctx);
      tools.fn(
        'web_search',
        handler: (ToolContext c) async => ToolResult.failure(
          '无法联网：所有搜索源都不可用。',
          error: const ToolError('SEARCH_UNAVAILABLE', 'boom'),
        ),
      );
      instrumentTools(ctx, telemetry: telemetry);

      await tools.call(const ToolCall(name: 'web_search'));

      expect(
          telemetry.recent.map((TelemetryEvent e) => e.name),
          <String>['tool.called', 'tool.failed']);
      final TelemetryEvent failed = telemetry.recent.last;
      expect(failed.data['tool'], 'web_search');
      expect(failed.data['error'], 'boom');
      ctx.dispose();
    });
  });

  group('TelemetryLlmProvider', () {
    test('发 llm.request', () async {
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      final TelemetryLlmProvider provider = TelemetryLlmProvider(
        _ScriptedProvider(<LlmResult>[_call('c1', 'get_time')]),
        telemetry: telemetry,
      );

      await provider.chat(<LlmMessage>[
        const LlmMessage('user', 'hi')
      ], tools: <Map<String, dynamic>>[
        <String, dynamic>{'name': 'get_time'}
      ]);

      final TelemetryEvent event = telemetry.recent.single;
      expect(event.name, 'llm.request');
      expect(event.data['toolCalls'], 1);
      expect(event.data['tools'], 1);
      await telemetry.close();
    });
  });

  group('AgentLoop 埋点', () {
    test('onEvent 产出 agent.round / agent.finished', () async {
      final ToolRegistry tools = ToolRegistry();
      tools.fn('get_time',
          handler: (ToolContext c) async => ToolResult.success('12:00'));
      final List<String> types = <String>[];
      final AgentLoop loop = AgentLoop(
        llm: _ScriptedProvider(
            <LlmResult>[_call('c1', 'get_time'), _text('12:00')]),
        tools: tools,
        onEvent: (String type, Map<String, Object?> data) => types.add(type),
      );

      await loop.run('现在几点');

      expect(types, containsAll(<String>['agent.round', 'agent.finished']));
    });

    test('provideAgentLoop 自动接上 telemetry', () async {
      final Context ctx = Context.root();
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      provideTelemetry(ctx, telemetry: telemetry);
      provideLlm(ctx,
          llm: FallbackLlm(<LlmProvider>[
            _ScriptedProvider(<LlmResult>[_text('hi')])
          ]));
      provideTools(ctx);

      final AgentLoop loop = provideAgentLoop(ctx);
      await loop.run('你好');

      expect(
          telemetry.recent.map((TelemetryEvent e) => e.name),
          containsAll(
              <String>['llm.request', 'agent.round', 'agent.finished']));
      ctx.dispose();
    });
  });

  group('provideTelemetry / ctx.telemetry', () {
    test('作为 telemetry 服务提供', () {
      final Context ctx = Context.root();
      final Telemetry telemetry = provideTelemetry(ctx);
      expect(identical(ctx.telemetry, telemetry), isTrue);
      ctx.dispose();
    });

    test('未提供时 ctx.telemetry 抛 StateError', () {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      expect(() => ctx.telemetry, throwsStateError);
    });
  });
}
