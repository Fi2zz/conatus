import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_alerting/conatus_alerting.dart';
import 'package:test/test.dart';

void main() {
  group('defaultAlertRules', () {
    late List<AlertRule> rules;
    late AlertContext ctx;

    setUp(() {
      rules = defaultAlertRules();
      ctx = AlertContext();
    });

    AlertRule ruleOf(String name) =>
        rules.firstWhere((AlertRule rule) => rule.name == name);

    bool evaluate(String name, TelemetryEvent event) =>
        ruleOf(name).condition(event, ctx);

    test('包含 8 条默认规则', () {
      expect(rules.map((r) => r.name), containsAll(<String>[
        'llm-slow',
        'llm-very-slow',
        'tool-slow',
        'tool-failures',
        'session-budget',
        'daily-budget',
        'agent-loop',
        'subagent-stuck',
      ]));
    });

    test('llm-slow 与 llm-very-slow 按 durationMs 分级', () {
      expect(evaluate('llm-slow', TelemetryEvent('llm.request', data: <String, Object?>{'durationMs': 35000})), isTrue);
      expect(evaluate('llm-slow', TelemetryEvent('llm.request', data: <String, Object?>{'durationMs': 5000})), isFalse);
      expect(evaluate('llm-very-slow', TelemetryEvent('llm.request', data: <String, Object?>{'durationMs': 65000})), isTrue);
      expect(evaluate('llm-very-slow', TelemetryEvent('llm.request', data: <String, Object?>{'durationMs': 35000})), isFalse);
    });

    test('tool-slow 按工具耗时', () {
      expect(evaluate('tool-slow', TelemetryEvent('tool.called', data: <String, Object?>{'durationMs': 15000})), isTrue);
      expect(evaluate('tool-slow', TelemetryEvent('tool.called', data: <String, Object?>{'durationMs': 500})), isFalse);
    });

    test('tool-failures 1 分钟内失败超过 5 次', () {
      expect(evaluate('tool-failures', TelemetryEvent('tool.failed')), isFalse);
      for (int i = 0; i < 5; i++) {
        evaluate('tool-failures', TelemetryEvent('tool.failed'));
      }
      expect(evaluate('tool-failures', TelemetryEvent('tool.failed')), isTrue,
          reason: '第 6 次失败触发');
    });

    test('session-budget 与 daily-budget 按成本', () {
      expect(evaluate('session-budget', TelemetryEvent('cost.recorded', data: <String, Object?>{'sessionCost': 1.5})), isTrue);
      expect(evaluate('daily-budget', TelemetryEvent('cost.recorded', data: <String, Object?>{'dailyCost': 12.0})), isTrue);
      expect(evaluate('daily-budget', TelemetryEvent('cost.recorded', data: <String, Object?>{'dailyCost': 3.0})), isFalse);
    });

    test('agent-loop 超过 20 步或收到 exceeded 事件', () {
      expect(evaluate('agent-loop', TelemetryEvent('agent.round', data: <String, Object?>{'step': 21})), isTrue);
      expect(evaluate('agent-loop', TelemetryEvent('agent.round', data: <String, Object?>{'step': 5})), isFalse);
      expect(evaluate('agent-loop', TelemetryEvent('agent.round.exceeded')), isTrue);
    });

    test('subagent-stuck 只记录不触发（暂缓）', () {
      expect(evaluate('subagent-stuck', TelemetryEvent('subagent.spawned', data: <String, Object?>{'id': 's1'})), isFalse);
      expect(evaluate('subagent-stuck', TelemetryEvent('subagent.finished')), isFalse);
    });
  });
}
