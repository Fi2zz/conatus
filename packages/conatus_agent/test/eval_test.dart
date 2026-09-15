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

void main() {
  group('defaultEvalJudge', () {
    const EvalCase base = EvalCase(id: 'c', input: 'x');

    test('期望工具为实际子集', () {
      const EvalCase c = EvalCase(
        id: 'c',
        input: '现在几点',
        expectedTools: <String>['get_time'],
      );
      const EvalResult ok = EvalResult(
        caseId: 'c',
        passed: false,
        actualTools: <String>['get_time'],
        actualOutput: '12:00',
        rounds: 1,
        duration: Duration.zero,
      );
      const EvalResult missing = EvalResult(
        caseId: 'c',
        passed: false,
        actualTools: <String>['web_search'],
        actualOutput: '12:00',
        rounds: 1,
        duration: Duration.zero,
      );
      expect(defaultEvalJudge(c, ok), isTrue);
      expect(defaultEvalJudge(c, missing), isFalse);
    });

    test('输出关键词与步数上限', () {
      const EvalResult result = EvalResult(
        caseId: 'c',
        passed: false,
        actualTools: <String>[],
        actualOutput: '今天是晴天',
        rounds: 3,
        duration: Duration.zero,
      );
      expect(
        defaultEvalJudge(
            const EvalCase(id: 'c', input: 'x', expectedOutput: '晴天'), result),
        isTrue,
      );
      expect(
        defaultEvalJudge(
            const EvalCase(id: 'c', input: 'x', expectedOutput: '下雨'), result),
        isFalse,
      );
      expect(
        defaultEvalJudge(
            const EvalCase(id: 'c', input: 'x', maxRounds: 2), result),
        isFalse,
      );
      expect(defaultEvalJudge(base, result), isTrue);
    });
  });

  group('Evaluator', () {
    test('evaluate 从 turn 提取实际行为并判分', () async {
      final Evaluator evaluator = Evaluator(
        run: (String input) async =>
            _turn('现在是 12:00', tools: <String>['get_time']),
      );

      final EvalResult result = await evaluator.evaluate(const EvalCase(
        id: 'time',
        input: '现在几点',
        expectedTools: <String>['get_time'],
        expectedOutput: '12:00',
      ));

      expect(result.passed, isTrue);
      expect(result.actualTools, <String>['get_time']);
      expect(result.actualOutput, '现在是 12:00');
      expect(result.rounds, 1);
    });

    test('runAll 汇总通过率与平均步数', () async {
      final Evaluator evaluator = Evaluator(
        run: (String input) async =>
            input == 'a' ? _turn('好', tools: <String>['t']) : _turn('差'),
      );

      final EvalReport report = await evaluator.runAll(const <EvalCase>[
        EvalCase(id: 'a', input: 'a', expectedTools: <String>['t']),
        EvalCase(id: 'b', input: 'b', expectedTools: <String>['t']),
      ]);

      expect(report.results, hasLength(2));
      expect(report.passedCount, 1);
      expect(report.passRate, 0.5);
      expect(report.averageRounds, 0.5);
    });

    test('compareTo 给出通过率与步数差', () async {
      final Evaluator evaluator = Evaluator(
        run: (String input) async => _turn('好', tools: <String>['t']),
      );
      final EvalReport report = await evaluator.runAll(const <EvalCase>[
        EvalCase(id: 'a', input: 'a', expectedTools: <String>['t']),
      ]);
      const EvalReport baseline = EvalReport(<EvalResult>[
        EvalResult(
          caseId: 'a',
          passed: false,
          actualTools: <String>[],
          actualOutput: '',
          rounds: 2,
          duration: Duration.zero,
        ),
      ]);

      final EvalDiff diff = report.compareTo(baseline);
      expect(diff.passRateDelta, 1.0);
      expect(diff.averageRoundsDelta, -1.0);
      expect(diff.toString(), contains('通过率'));
    });
  });

  group('序列化', () {
    test('EvalCase 往返', () {
      const EvalCase evalCase = EvalCase(
        id: 'c',
        input: '现在几点',
        expectedTools: <String>['get_time'],
        expectedOutput: '12:00',
        maxRounds: 3,
      );
      final EvalCase restored = EvalCase.fromJson(evalCase.toJson());
      expect(restored.id, 'c');
      expect(restored.expectedTools, <String>['get_time']);
      expect(restored.expectedOutput, '12:00');
      expect(restored.maxRounds, 3);
    });

    test('EvalReport 往返', () {
      const EvalReport report = EvalReport(<EvalResult>[
        EvalResult(
          caseId: 'a',
          passed: true,
          actualTools: <String>['t'],
          actualOutput: 'ok',
          rounds: 1,
          duration: Duration(milliseconds: 5),
        ),
      ]);
      final EvalReport restored = EvalReport.fromJson(report.toJson());
      expect(restored.passRate, 1.0);
      expect(restored.results.single.actualTools, <String>['t']);
      expect(restored.results.single.duration, const Duration(milliseconds: 5));
    });
  });
}
