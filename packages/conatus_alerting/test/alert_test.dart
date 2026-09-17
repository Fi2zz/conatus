import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_alerting/conatus_alerting.dart';
import 'package:test/test.dart';

void main() {
  group('Alert', () {
    Alert sample({String rule = 'llm-slow'}) => Alert(
          id: 'a1',
          rule: rule,
          severity: AlertSeverity.warning,
          event: TelemetryEvent('llm.request',
              data: <String, Object?>{'durationMs': 35000}),
          firedAt: DateTime(2026, 9, 17, 10, 30),
          sessionId: 's1',
          context: <String, Object?>{'k': 'v'},
        );

    test('summary 按规则口语化', () {
      expect(sample().summary, contains('35000'));
      expect(sample(rule: 'tool-slow').summary, contains('工具'));
      expect(sample(rule: 'unknown-rule').summary, 'llm.request');
    });

    test('JSON 往返保留全部字段', () {
      final Alert original = sample();
      final Alert restored = Alert.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.rule, original.rule);
      expect(restored.severity, AlertSeverity.warning);
      expect(restored.sessionId, 's1');
      expect(restored.firedAt, original.firedAt);
      expect(restored.event.name, 'llm.request');
      expect(restored.event.data['durationMs'], 35000);
      expect(restored.context['k'], 'v');
    });

    test('fromJson 宽松处理缺失字段', () {
      final Alert restored = Alert.fromJson(const <String, Object?>{});
      expect(restored.id, '');
      expect(restored.severity, AlertSeverity.warning);
      expect(restored.event.name, '');
    });
  });
}
