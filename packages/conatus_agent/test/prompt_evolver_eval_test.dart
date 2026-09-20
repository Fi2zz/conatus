import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

AgentTurn _turn(String reply, {List<String> tools = const <String>[]}) =>
    AgentTurn(
      reply: reply,
      messages: const <LlmMessage>[],
      steps: <AgentStep>[
        for (final String name in tools)
          AgentStep(
            call: LlmToolCall(id: 'c', name: name),
            result: ToolResult.success(''),
          ),
      ],
    );

/// 当前 `persona` section 的装配文本；未注册返回空串。
String _sectionText(SystemPrompt prompt) {
  for (final AssembledSection section in prompt.assemble().sections) {
    if (section.name == 'persona') return section.text;
  }
  return '';
}

/// 文本含「改进」即通过（变体胜出），否则失败（基线失败）。
Evaluator _abEvaluator(SystemPrompt prompt) => Evaluator(
      run: (String input) async => _sectionText(prompt).contains('改进')
          ? _turn('ok', tools: <String>['t'])
          : _turn('差'),
    );

/// 文本含「改进」即失败（变体劣化），否则通过（基线胜出）。
Evaluator _regressionEvaluator(SystemPrompt prompt) => Evaluator(
      run: (String input) async => _sectionText(prompt).contains('改进')
          ? _turn('差')
          : _turn('ok', tools: <String>['t']),
    );

const List<EvalCase> _cases = <EvalCase>[
  EvalCase(id: 'a', input: 'x', expectedTools: <String>['t']),
];

PromptVariant _variant(String id, String text) => PromptVariant(
      id: id,
      sectionName: 'persona',
      text: text,
      reason: 'r',
      createdAt: DateTime.now(),
    );

void main() {
  group('evaluate', () {
    test('A/B 对比基线（原文）与变体，计算 improvement 并恢复 section', () async {
      final SystemPrompt prompt = SystemPrompt()..add('原文', name: 'persona');
      final DefaultPromptEvolver evolver = DefaultPromptEvolver(
        llm: _ScriptedProvider(<String>[]),
        evaluator: _abEvaluator(prompt),
        prompt: prompt,
        evalCases: _cases,
      );

      final EvolutionResult result =
          await evolver.evaluate(_variant('v1', '改进版'));

      expect(result.baselineScore, 0);
      expect(result.variantScore, 1);
      expect(result.improvement, 1);
      expect(result.decision, EvolutionDecision.promote);
      expect(result.variant.score, 1);
      expect(_sectionText(prompt), '原文'); // 评估结束后恢复
    });

    test('improvement 为 0 时决策 insufficient', () async {
      final SystemPrompt prompt = SystemPrompt()..add('原文', name: 'persona');
      final DefaultPromptEvolver evolver = DefaultPromptEvolver(
        llm: _ScriptedProvider(<String>[]),
        evaluator: Evaluator(
            run: (String input) async => _turn('ok', tools: <String>['t'])),
        prompt: prompt,
        evalCases: _cases,
      );
      final EvolutionResult result =
          await evolver.evaluate(_variant('v1', '改进版'));
      expect(result.improvement, 0);
      expect(result.decision, EvolutionDecision.insufficient);
      expect(_sectionText(prompt), '原文');
    });

    test('变体劣化时决策 reject', () async {
      final SystemPrompt prompt = SystemPrompt()..add('原文', name: 'persona');
      final DefaultPromptEvolver evolver = DefaultPromptEvolver(
        llm: _ScriptedProvider(<String>[]),
        evaluator: _regressionEvaluator(prompt),
        prompt: prompt,
        evalCases: _cases,
      );
      final EvolutionResult result =
          await evolver.evaluate(_variant('v1', '改进版'));
      expect(result.improvement, -1);
      expect(result.decision, EvolutionDecision.reject);
      expect(_sectionText(prompt), '原文');
    });

    test('evalCases 为空时决策 insufficient', () async {
      final SystemPrompt prompt = SystemPrompt()..add('原文', name: 'persona');
      final DefaultPromptEvolver evolver = DefaultPromptEvolver(
        llm: _ScriptedProvider(<String>[]),
        evaluator: _abEvaluator(prompt),
        prompt: prompt,
      );
      final EvolutionResult result =
          await evolver.evaluate(_variant('v1', '改进版'));
      expect(result.decision, EvolutionDecision.insufficient);
    });

    test('按 token 预算截断用例', () async {
      int calls = 0;
      final Evaluator counting = Evaluator(run: (String input) async {
        calls++;
        return _turn('ok', tools: <String>['t']);
      });
      final SystemPrompt prompt = SystemPrompt()..add('原文', name: 'persona');
      final DefaultPromptEvolver evolver = DefaultPromptEvolver(
        llm: _ScriptedProvider(<String>[]),
        evaluator: counting,
        prompt: prompt,
        evalCases: const <EvalCase>[
          EvalCase(id: 'a', input: 'x'),
          EvalCase(id: 'b', input: 'y'),
        ],
        maxBudgetPerRun: 1,
      );
      await evolver.evaluate(_variant('v1', '改进版'));
      expect(calls, 2); // 基线 + 变体各只跑 1 条
    });
  });
}

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
