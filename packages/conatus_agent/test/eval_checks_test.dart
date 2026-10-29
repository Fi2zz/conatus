import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

const EvalResult _result = EvalResult(
  caseId: 'c',
  passed: false,
  actualTools: <String>['get_time'],
  actualOutput: '现在是 12:00，天气晴',
  rounds: 3,
  duration: Duration.zero,
);

void main() {
  group('EvalCheck', () {
    test('输出包含 / 不包含', () {
      expect(const OutputContains('12:00').evaluate(_result), isTrue);
      expect(const OutputContains('13:00').evaluate(_result), isFalse);
      expect(
          const OutputContains('下雨', absent: true).evaluate(_result), isTrue);
      expect(
          const OutputContains('晴', absent: true).evaluate(_result), isFalse);
    });

    test('正则匹配 / 不匹配', () {
      expect(OutputMatches(r'1\d:\d\d').evaluate(_result), isTrue);
      expect(OutputMatches(r'^\d+$').evaluate(_result), isFalse);
      expect(OutputMatches(r'下雨', absent: true).evaluate(_result), isTrue);
    });

    test('非法正则构造时抛错', () {
      expect(() => OutputMatches('['), throwsFormatException);
    });

    test('工具调用：必须调用与禁止调用', () {
      expect(const ToolUse('get_time').evaluate(_result), isTrue);
      expect(const ToolUse('websearch').evaluate(_result), isFalse);
      expect(
        const ToolUse('websearch', required: false).evaluate(_result),
        isTrue,
      );
      expect(
        const ToolUse('get_time', required: false).evaluate(_result),
        isFalse,
      );
    });

    test('步数上限', () {
      expect(const RoundsWithin(3).evaluate(_result), isTrue);
      expect(const RoundsWithin(2).evaluate(_result), isFalse);
    });

    test('JSON 往返保留类型与参数', () {
      final List<EvalCheck> checks = <EvalCheck>[
        const OutputContains('12:00'),
        const OutputContains('下雨', absent: true),
        OutputMatches(r'1\d'),
        const ToolUse('get_time'),
        const ToolUse('websearch', required: false),
        const RoundsWithin(5),
      ];

      final List<EvalCheck> restored = <EvalCheck>[
        for (final EvalCheck check in checks)
          EvalCheck.fromJson(check.toJson()),
      ];

      expect(restored.map((EvalCheck c) => c.toJson()).toList(),
          checks.map((EvalCheck c) => c.toJson()).toList());
    });

    test('未知类型抛 FormatException', () {
      expect(
        () => EvalCheck.fromJson(<String, Object?>{'type': 'nope'}),
        throwsFormatException,
      );
    });
  });

  group('defaultEvalJudge + checks', () {
    test('全部断言通过才通过', () {
      const EvalCase ok = EvalCase(
        id: 'c',
        input: 'x',
        expectedTools: <String>['get_time'],
        checks: <EvalCheck>[
          OutputContains('12:00'),
          ToolUse('get_time'),
          RoundsWithin(4),
        ],
      );

      expect(defaultEvalJudge(ok, _result), isTrue);
      expect(
        defaultEvalJudge(
          const EvalCase(
            id: 'c',
            input: 'x',
            checks: <EvalCheck>[OutputContains('13:00')],
          ),
          _result,
        ),
        isFalse,
      );
    });

    test('断言与旧字段同时生效', () {
      const EvalCase evalCase = EvalCase(
        id: 'c',
        input: 'x',
        expectedTools: <String>['websearch'],
        checks: <EvalCheck>[OutputContains('12:00')],
      );

      expect(defaultEvalJudge(evalCase, _result), isFalse);
    });
  });

  group('EvalCase 序列化', () {
    test('checks 往返', () {
      const EvalCase evalCase = EvalCase(
        id: 'c',
        input: 'x',
        checks: <EvalCheck>[
          OutputContains('12:00'),
          RoundsWithin(3),
        ],
      );

      final EvalCase restored = EvalCase.fromJson(evalCase.toJson());

      expect(restored.checks, hasLength(2));
      expect(restored.checks.first.evaluate(_result), isTrue);
    });
  });

  final List<EvalCase> suiteCases = <EvalCase>[
    const EvalCase(id: 'a', input: 'a', checks: <EvalCheck>[RoundsWithin(2)]),
    const EvalCase(
        id: 'b', input: 'b', checks: <EvalCheck>[OutputContains('x')]),
  ];

  group('EvalSuite', () {
    final List<EvalCase> cases = suiteCases;

    test('同一用例集 hash 稳定，与顺序无关', () {
      final EvalSuite forward = EvalSuite(cases);
      final EvalSuite backward = EvalSuite(cases.reversed.toList());

      expect(forward.hash, backward.hash);
    });

    test('改一条断言 hash 就变', () {
      final EvalSuite original = EvalSuite(cases);
      final EvalSuite changed = EvalSuite(<EvalCase>[
        cases.first,
        const EvalCase(
          id: 'b',
          input: 'b',
          checks: <EvalCheck>[OutputContains('y')],
        ),
      ]);

      expect(changed.hash, isNot(original.hash));
    });

    test('JSON 往返保留 hash 与用例', () {
      final EvalSuite suite = EvalSuite(cases);
      final EvalSuite restored = EvalSuite.fromJson(suite.toJson());

      expect(restored.hash, suite.hash);
      expect(restored.cases, hasLength(2));
    });

    test('hash 被篡改时拒绝加载', () {
      final Map<String, Object?> json = EvalSuite(cases).toJson();
      json['hash'] = 'deadbeef';

      expect(() => EvalSuite.fromJson(json), throwsFormatException);
    });
  });

  group('EvalReport.suiteHash', () {
    test('runAll 记录用例集 hash', () async {
      final Evaluator evaluator = Evaluator(
        run: (String input) async => const AgentTurn(
          reply: 'ok',
          steps: <AgentStep>[],
          messages: <LlmMessage>[],
        ),
      );

      final EvalReport report = await evaluator.runAll(suiteCases);

      expect(report.suiteHash, EvalSuite(suiteCases).hash);
    });

    test('序列化往返保留 hash', () async {
      const EvalReport report = EvalReport(
        <EvalResult>[
          EvalResult(
            caseId: 'a',
            passed: true,
            actualTools: <String>[],
            actualOutput: 'ok',
            rounds: 0,
            duration: Duration.zero,
          ),
        ],
        suiteHash: 'abc123',
      );

      expect(EvalReport.fromJson(report.toJson()).suiteHash, 'abc123');
    });

    test('用例集不同时 compareTo 拒绝比较', () {
      const EvalReport a = EvalReport(<EvalResult>[], suiteHash: 'aaa');
      const EvalReport b = EvalReport(<EvalResult>[], suiteHash: 'bbb');

      expect(() => a.compareTo(b), throwsStateError);
    });

    test('任一侧没有 hash 时仍可比较', () {
      const EvalReport a = EvalReport(<EvalResult>[], suiteHash: 'aaa');
      const EvalReport b = EvalReport(<EvalResult>[]);

      expect(a.compareTo(b).passRateDelta, 0);
    });
  });
}
