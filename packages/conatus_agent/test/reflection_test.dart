import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _ReplyProvider implements LlmProvider {
  _ReplyProvider(this.reply);

  final String reply;
  int calls = 0;

  @override
  String get name => 'reflect';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls++;
    return LlmResult(content: reply, provider: 'reflect', model: 'm');
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

class _ScriptedMain implements LlmProvider {
  _ScriptedMain(this.script);

  final List<LlmResult> script;
  int calls = 0;

  @override
  String get name => 'main';

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
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

LlmResult _text(String content) =>
    LlmResult(content: content, provider: 'main', model: 'm');

LlmResult _call(String id, String name) => LlmResult(
      content: '',
      provider: 'main',
      model: 'm',
      toolCalls: <LlmToolCall>[LlmToolCall(id: id, name: name)],
    );

void main() {
  group('ReflectionDecision.parse', () {
    test('解析 JSON decision', () {
      expect(ReflectionDecision.parse('{"decision":"retry"}').action,
          ReflectionAction.retry);
      expect(ReflectionDecision.parse('{"decision":"replan"}').action,
          ReflectionAction.replan);
      expect(ReflectionDecision.parse('{"decision":"continue"}').action,
          ReflectionAction.continueRun);
    });

    test('关键词兜底与默认', () {
      expect(ReflectionDecision.parse('应该 retry 一次').action,
          ReflectionAction.retry);
      expect(ReflectionDecision.parse('需要 replan').action,
          ReflectionAction.replan);
      expect(ReflectionDecision.parse('看起来没问题').action,
          ReflectionAction.continueRun);
    });
  });

  group('Reflector.shouldReflect', () {
    final ToolRegistry tools = ToolRegistry()
      ..fn('read', handler: (ToolContext c) async => ToolResult.success(''))
      ..fn('write',
          riskLevel: ToolRisk.medium,
          handler: (ToolContext c) async => ToolResult.success(''));
    final Tool read = tools.get('read')!;
    final Tool write = tools.get('write')!;
    final ToolResult ok = ToolResult.success('x');
    final ToolResult bad = ToolResult.failure('e');

    test('onError 只在失败时', () {
      final Reflector r = Reflector(llm: _ReplyProvider('continue'));
      expect(r.shouldReflect(read, ok), isFalse);
      expect(r.shouldReflect(read, bad), isTrue);
    });

    test('onRisk 看风险等级', () {
      final Reflector r = Reflector(
          llm: _ReplyProvider('x'), strategy: ReflectionStrategy.onRisk);
      expect(r.shouldReflect(read, bad), isFalse);
      expect(r.shouldReflect(write, ok), isTrue);
    });

    test('never / always', () {
      expect(
          Reflector(
                  llm: _ReplyProvider('x'), strategy: ReflectionStrategy.never)
              .shouldReflect(read, bad),
          isFalse);
      expect(
          Reflector(
                  llm: _ReplyProvider('x'), strategy: ReflectionStrategy.always)
              .shouldReflect(read, ok),
          isTrue);
    });
  });

  group('reflectAndRetry', () {
    test('retry 重跑一次并采用新结果', () async {
      final ToolRegistry tools = ToolRegistry();
      int attempts = 0;
      tools.fn('flaky', handler: (ToolContext c) async {
        attempts++;
        return attempts == 1
            ? ToolResult.failure('boom')
            : ToolResult.success('ok');
      });
      final _ReplyProvider reflect = _ReplyProvider('{"decision":"retry"}');
      final Reflector reflector = Reflector(
        llm: reflect,
        strategy: ReflectionStrategy.always,
      );

      final ToolResult outcome = await reflectAndRetry(
        reflector: reflector,
        tools: tools,
        task: 't',
        call: const LlmToolCall(id: 'c1', name: 'flaky'),
        initial: ToolResult.failure('boom'),
        invoke: (LlmToolCall call) async {
          attempts++;
          return ToolResult.success('ok');
        },
      );

      expect(outcome.content, 'ok');
      expect(reflect.calls, 1);
    });

    test('replan 触发回调并保留原结果', () async {
      final ToolRegistry tools = ToolRegistry()
        ..fn('t', handler: (ToolContext c) async => ToolResult.success(''));
      final Reflector reflector = Reflector(
        llm: _ReplyProvider('{"decision":"replan"}'),
        strategy: ReflectionStrategy.always,
      );
      var replanned = false;

      final ToolResult outcome = await reflectAndRetry(
        reflector: reflector,
        tools: tools,
        task: 't',
        call: const LlmToolCall(id: 'c1', name: 't'),
        initial: ToolResult.failure('bad'),
        invoke: (LlmToolCall call) async => ToolResult.success('unused'),
        onReplan: () => replanned = true,
      );

      expect(replanned, isTrue);
      expect(outcome.isError, isTrue);
    });
  });

  group('AgentLoop 集成', () {
    test('onError 失败重试后继续', () async {
      final ToolRegistry tools = ToolRegistry();
      int attempts = 0;
      tools.fn('flaky', handler: (ToolContext c) async {
        attempts++;
        return attempts == 1
            ? ToolResult.failure('boom')
            : ToolResult.success('ok');
      });
      final _ScriptedMain main =
          _ScriptedMain(<LlmResult>[_call('c1', 'flaky'), _text('完成')]);
      final _ReplyProvider reflect = _ReplyProvider('{"decision":"retry"}');
      final AgentLoop loop = AgentLoop(
        llm: main,
        tools: tools,
        reflector: Reflector(llm: reflect),
      );

      final AgentTurn turn = await loop.run('试试');

      expect(turn.reply, '完成');
      expect(attempts, 2);
      expect(reflect.calls, 1);
      expect(turn.steps.single.result.content, 'ok');
    });
  });

  group('provideReflection', () {
    test('策略取上下文的 reflectionStrategy，服务键为 reflection', () {
      final Context ctx = Context.root();
      provideLlm(ctx, llm: FallbackLlm(<LlmProvider>[_ReplyProvider('x')]));
      ctx.provide('reflectionStrategy', 'always');

      final Reflector reflector = provideReflection(ctx);

      expect(reflector.strategy, ReflectionStrategy.always);
      expect(
          identical(ctx.require<Reflector>('reflection'), reflector), isTrue);
      ctx.dispose();
    });

    test('默认 onError', () {
      final Context ctx = Context.root();
      provideLlm(ctx, llm: FallbackLlm(<LlmProvider>[_ReplyProvider('x')]));
      expect(provideReflection(ctx).strategy, ReflectionStrategy.onError);
      ctx.dispose();
    });

    test('parseReflectionStrategy 识别与拒绝', () {
      expect(parseReflectionStrategy('on_risk'), isNull);
      expect(parseReflectionStrategy('onRisk'), ReflectionStrategy.onRisk);
      expect(parseReflectionStrategy(null), isNull);
    });
  });
}
