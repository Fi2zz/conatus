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
  group('promote', () {
    test('通过阈值且审批通过：替换 section、存档、埋点', () async {
      final SystemPrompt prompt = SystemPrompt()..add('原文', name: 'persona');
      final AutoApproval approval = AutoApproval(true);
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      final DefaultPromptEvolver evolver = DefaultPromptEvolver(
        llm: _ScriptedProvider(<String>[]),
        evaluator: _abEvaluator(prompt),
        prompt: prompt,
        evalCases: _cases,
        approval: approval,
        telemetry: telemetry,
      );

      final bool promoted = await evolver.promote(_variant('v1', '改进版'));

      expect(promoted, isTrue);
      expect(approval.requests, 1);
      expect(_sectionText(prompt), '改进版');
      expect(evolver.current?.id, 'v1');
      expect(evolver.history, hasLength(2)); // 初始快照 + v1
      expect(telemetry.recent.map((TelemetryEvent e) => e.name),
          contains('prompt.promoted'));
    });

    test('审批拒绝：不替换、不存档', () async {
      final SystemPrompt prompt = SystemPrompt()..add('原文', name: 'persona');
      final AutoApproval approval = AutoApproval(false);
      final DefaultPromptEvolver evolver = DefaultPromptEvolver(
        llm: _ScriptedProvider(<String>[]),
        evaluator: _abEvaluator(prompt),
        prompt: prompt,
        evalCases: _cases,
        approval: approval,
      );
      final bool promoted = await evolver.promote(_variant('v1', '改进版'));
      expect(promoted, isFalse);
      expect(approval.requests, 1);
      expect(_sectionText(prompt), '原文');
      expect(evolver.history, isEmpty);
      expect(evolver.current, isNull);
    });

    test('improvement 不足时不打扰审批', () async {
      final SystemPrompt prompt = SystemPrompt()..add('原文', name: 'persona');
      final AutoApproval approval = AutoApproval(true);
      final DefaultPromptEvolver evolver = DefaultPromptEvolver(
        llm: _ScriptedProvider(<String>[]),
        evaluator: Evaluator(run: (String input) async => _turn('差')),
        prompt: prompt,
        evalCases: _cases,
        approval: approval,
      );
      final bool promoted = await evolver.promote(_variant('v1', '改进版'));
      expect(promoted, isFalse);
      expect(approval.requests, 0);
      expect(_sectionText(prompt), '原文');
    });
  });

  group('rollback', () {
    test('回滚到历史版本：恢复 section、存档、埋点', () async {
      final SystemPrompt prompt = SystemPrompt()..add('原文', name: 'persona');
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      final DefaultPromptEvolver evolver = DefaultPromptEvolver(
        llm: _ScriptedProvider(<String>[]),
        evaluator: _abEvaluator(prompt),
        prompt: prompt,
        evalCases: _cases,
        telemetry: telemetry,
      );
      await evolver.promote(_variant('v1', '改进版'));
      final String initialId = evolver.history.first.id;

      await evolver.rollback(initialId);

      expect(_sectionText(prompt), '原文');
      expect(evolver.current?.id, initialId);
      expect(telemetry.recent.map((TelemetryEvent e) => e.name),
          contains('prompt.rolled_back'));
    });

    test('未知变体 id 抛 StateError', () async {
      final DefaultPromptEvolver evolver = DefaultPromptEvolver(
        llm: _ScriptedProvider(<String>[]),
        evaluator: Evaluator(run: (String input) async => _turn('差')),
        prompt: SystemPrompt()..add('原文', name: 'persona'),
      );
      await expectLater(evolver.rollback('nope'), throwsStateError);
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
