import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _FixedProvider implements LlmProvider {
  _FixedProvider(this.result);

  final LlmResult result;

  @override
  String get name => 'fixed';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async =>
      result;

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

LlmResult _charged(String content) => LlmResult(
      content: content,
      provider: 'fixed',
      model: 'm',
      usage: <String, dynamic>{
        'prompt_tokens': 1000000,
        'completion_tokens': 0,
      },
    );

const ModelRate _rate = ModelRate(
  inputPerMillion: 3,
  cachedPerMillion: 1,
  outputPerMillion: 30,
);

void main() {
  test('llm.request 带归一 token 与成本', () async {
    final InMemoryTelemetry sink = InMemoryTelemetry();
    final TelemetryLlmProvider provider = TelemetryLlmProvider(
      _FixedProvider(_charged('ok')),
      telemetry: sink,
      rate: _rate,
    );

    await provider.chat(const <LlmMessage>[]);

    final TelemetryEvent event = sink.recent.single;
    expect(event.name, 'llm.request');
    expect(event.data['promptTokens'], 1000000);
    expect(event.data['cachedTokens'], 0);
    expect(event.data['completionTokens'], 0);
    expect(event.data['cost'], closeTo(3, 1e-9));
  });

  test('未注入费率时不出现 cost 键，token 仍可见', () async {
    final InMemoryTelemetry sink = InMemoryTelemetry();
    final TelemetryLlmProvider provider = TelemetryLlmProvider(
      _FixedProvider(_charged('ok')),
      telemetry: sink,
    );

    await provider.chat(const <LlmMessage>[]);

    final TelemetryEvent event = sink.recent.single;
    expect(event.data.containsKey('cost'), isFalse);
    expect(event.data['promptTokens'], 1000000);
  });

  test('AgentTurn 汇总本轮成本与用量', () async {
    final AgentLoop loop = AgentLoop(
      llm: _FixedProvider(_charged('done')),
      tools: ToolRegistry(),
      rate: _rate,
    );

    final AgentTurn turn = await loop.run('hi');

    expect(turn.cost, closeTo(3, 1e-9));
    expect(turn.tokens.prompt, 1000000);
    expect(turn.usage, hasLength(1));
  });

  test('无费率时 AgentTurn.cost 为 null，用量照常累计', () async {
    final AgentLoop loop = AgentLoop(
      llm: _FixedProvider(_charged('done')),
      tools: ToolRegistry(),
    );

    final AgentTurn turn = await loop.run('hi');

    expect(turn.cost, isNull);
    expect(turn.tokens.prompt, 1000000);
  });

  test('agent.finished 事件带成本', () async {
    final Map<String, Object?> finished = <String, Object?>{};
    final AgentLoop loop = AgentLoop(
      llm: _FixedProvider(_charged('done')),
      tools: ToolRegistry(),
      rate: _rate,
      onEvent: (String type, Map<String, Object?> data) {
        if (type == 'agent.finished') finished.addAll(data);
      },
    );

    await loop.run('hi');

    expect(finished['cost'], closeTo(3, 1e-9));
    expect(finished['steps'], 0);
  });

  test('provideAgentLoop 从上下文读取 modelRate 开关', () async {
    final Context ctx = Context.root();
    addTearDown(ctx.dispose);
    provideTools(ctx);
    ctx.provide('llm', _FixedProvider(_charged('done')));
    ctx.provide('modelRate', _rate);

    final AgentTurn turn = await provideAgentLoop(ctx).run('hi');

    expect(turn.cost, closeTo(3, 1e-9));
  });

  test('未提供 modelRate 时 provideAgentLoop 保持零成本', () async {
    final Context ctx = Context.root();
    addTearDown(ctx.dispose);
    provideTools(ctx);
    ctx.provide('llm', _FixedProvider(_charged('done')));

    final AgentTurn turn = await provideAgentLoop(ctx).run('hi');

    expect(turn.cost, isNull);
  });
}
