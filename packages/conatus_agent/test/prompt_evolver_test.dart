import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

/// 按脚本回复的 LLM，并记录收到的请求。
class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.replies);

  final List<String> replies;
  final List<List<LlmMessage>> requests = <List<LlmMessage>>[];
  int _index = 0;

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    requests.add(messages);
    final String reply = replies[_index.clamp(0, replies.length - 1)];
    _index++;
    return LlmResult(content: reply, provider: name, model: 'test');
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

SessionEvent _trace(String text) => SessionEvent.create(
      sessionId: 's1',
      type: kUserMessageEvent,
      seq: 0,
      data: <String, Object?>{'text': text},
    );

void main() {
  group('analyzeFailurePatterns', () {
    test('构造分析 prompt 并返回 LLM 结论', () async {
      final _ScriptedProvider llm = _ScriptedProvider(<String>['共性失败模式']);
      final String patterns =
          await analyzeFailurePatterns(llm, <SessionEvent>[_trace('任务A')]);
      expect(patterns, '共性失败模式');
      expect(llm.requests, hasLength(1));
      expect(llm.requests.single.first.role, 'system');
      expect(llm.requests.single.last.content, contains('失败模式'));
      expect(
          llm.requests.single.last.content, contains('user/message(text=任务A)'));
    });
  });

  group('generateVariant', () {
    test('基于当前 section 生成变体并记录演化链', () async {
      final _ScriptedProvider llm =
          _ScriptedProvider(<String>['## 改进后的 persona']);
      final SystemPrompt prompt = SystemPrompt()
        ..add('你是一个助手。', name: 'persona');
      final PromptVariant variant = await generateVariant(
        llm: llm,
        prompt: prompt,
        sectionName: 'persona',
        failurePatterns: '模式X',
        parentId: 'p0',
      );
      expect(variant.id, startsWith('variant-'));
      expect(variant.sectionName, 'persona');
      expect(variant.text, '## 改进后的 persona');
      expect(variant.reason, '模式X');
      expect(variant.parentId, 'p0');
      expect(llm.requests.single.last.content, contains('persona'));
      expect(llm.requests.single.last.content, contains('你是一个助手。'));
      expect(llm.requests.single.last.content, contains('模式X'));
    });

    test('section 未注册时抛 StateError', () async {
      final SystemPrompt prompt = SystemPrompt();
      await expectLater(
        generateVariant(
            llm: _ScriptedProvider(<String>['x']),
            prompt: prompt,
            sectionName: 'nope',
            failurePatterns: 'f'),
        throwsStateError,
      );
    });
  });

  group('propose', () {
    final List<SessionEvent> traces =
        List<SessionEvent>.generate(3, (int i) => _trace('任务$i'));

    test('轨迹不足 minTraces 时返回 null 且不调 LLM', () async {
      final _ScriptedProvider llm = _ScriptedProvider(<String>['a', 'b']);
      final DefaultPromptEvolver evolver = DefaultPromptEvolver(
        llm: llm,
        evaluator: Evaluator(
            run: (String input) async => const AgentTurn(
                reply: 'ok', messages: <LlmMessage>[], steps: <AgentStep>[])),
        prompt: SystemPrompt()..add('原文', name: 'persona'),
      );
      final PromptVariant? variant = await evolver.propose(
          sectionName: 'persona', lowQualityTraces: traces);
      expect(variant, isNull);
      expect(llm.requests, isEmpty);
    });

    test('轨迹充足时走失败分析 + 变体生成并埋点', () async {
      final _ScriptedProvider llm =
          _ScriptedProvider(<String>['失败模式A', '改进文本']);
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      final DefaultPromptEvolver evolver = DefaultPromptEvolver(
        llm: llm,
        evaluator: Evaluator(
            run: (String input) async => const AgentTurn(
                reply: 'ok', messages: <LlmMessage>[], steps: <AgentStep>[])),
        prompt: SystemPrompt()..add('原文', name: 'persona'),
        telemetry: telemetry,
        minTraces: 3,
      );
      final PromptVariant? variant = await evolver.propose(
          sectionName: 'persona', lowQualityTraces: traces);
      expect(variant, isNotNull);
      expect(variant!.text, '改进文本');
      expect(variant.reason, '失败模式A');
      expect(llm.requests, hasLength(2));
      expect(telemetry.recent.map((TelemetryEvent e) => e.name),
          contains('prompt.proposed'));
    });
  });

  group('providePromptEvolver', () {
    test('上下文缺 llm 时抛 StateError', () {
      final Context ctx = Context.root();
      expect(
        () => providePromptEvolver(
          ctx,
          evaluator: Evaluator(
              run: (String input) async => const AgentTurn(
                  reply: 'ok', messages: <LlmMessage>[], steps: <AgentStep>[])),
          sessionLog: InMemorySessionLog(),
          prompt: SystemPrompt(),
        ),
        throwsStateError,
      );
    });

    test('提供服务并可从上下文取回', () {
      final Context ctx = Context.root()
        ..provide('llm', _ScriptedProvider(<String>[]));
      final PromptEvolver evolver = providePromptEvolver(
        ctx,
        evaluator: Evaluator(
            run: (String input) async => const AgentTurn(
                reply: 'ok', messages: <LlmMessage>[], steps: <AgentStep>[])),
        sessionLog: InMemorySessionLog(),
        prompt: SystemPrompt()..add('原文', name: 'persona'),
        evalCases: const <EvalCase>[EvalCase(id: 'a', input: 'x')],
      );
      expect(ctx.promptEvolver, same(evolver));
    });
  });
}
