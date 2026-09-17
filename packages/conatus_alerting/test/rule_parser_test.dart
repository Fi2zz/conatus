import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_alerting/conatus_alerting.dart';
import 'package:test/test.dart';

void main() {
  group('RuleParser', () {
    test('解析字段比较条件', () {
      final List<AlertRule> rules = RuleParser.parse(<String, Object?>{
        'rules': <Object?>[
          <String, Object?>{
            'name': 'llm-slow',
            'severity': 'warning',
            'description': 'LLM 慢',
            'cooldown': 300,
            'condition': <String, Object?>{
              'event': 'llm.request',
              'field': 'durationMs',
              'operator': '>',
              'value': 30000,
            },
          },
        ],
      });

      expect(rules, hasLength(1));
      final AlertRule rule = rules.single;
      expect(rule.name, 'llm-slow');
      expect(rule.severity, AlertSeverity.warning);
      expect(rule.cooldown, const Duration(seconds: 300));
      expect(rule.description, 'LLM 慢');

      final AlertContext ctx = AlertContext();
      expect(rule.condition(TelemetryEvent('llm.request', data: <String, Object?>{'durationMs': 35000}), ctx), isTrue);
      expect(rule.condition(TelemetryEvent('llm.request', data: <String, Object?>{'durationMs': 5000}), ctx), isFalse);
    });

    test('解析窗口计数条件', () {
      final List<AlertRule> rules = RuleParser.parse(<String, Object?>{
        'rules': <Object?>[
          <String, Object?>{
            'name': 'tool-failures',
            'severity': 'critical',
            'condition': <String, Object?>{
              'event': 'tool.failed',
              'window': 60,
              'count': 5,
              'operator': '>',
            },
          },
        ],
      });

      final AlertContext ctx = AlertContext();
      final bool Function(TelemetryEvent, AlertContext) condition =
          rules.single.condition;
      for (int i = 0; i < 5; i++) {
        expect(condition(TelemetryEvent('tool.failed'), ctx), isFalse);
      }
      expect(condition(TelemetryEvent('tool.failed'), ctx), isTrue);
    });

    test('事件名不匹配不触发', () {
      final List<AlertRule> rules = RuleParser.parse(<String, Object?>{
        'rules': <Object?>[
          <String, Object?>{
            'name': 'r',
            'severity': 'info',
            'condition': <String, Object?>{
              'event': 'llm.request',
              'field': 'durationMs',
              'operator': '>',
              'value': 100,
            },
          },
        ],
      });
      expect(rules.single.condition(TelemetryEvent('tool.called'), AlertContext()), isFalse);
    });

    test('字段比较支持各运算符', () {
      final List<AlertRule> rules = RuleParser.parse(<String, Object?>{
        'rules': <Object?>[
          for (final String op in <String>['>', '>=', '<', '<=', '==', '!='])
            <String, Object?>{
              'name': 'op-$op',
              'severity': 'info',
              'condition': <String, Object?>{
                'event': 'e',
                'field': 'n',
                'operator': op,
                'value': 5,
              },
            },
        ],
      });

      for (final AlertRule rule in rules) {
        final bool Function(TelemetryEvent, AlertContext) condition =
            rule.condition;
        switch (rule.name) {
          case 'op->':
            expect(condition(TelemetryEvent('e', data: <String, Object?>{'n': 6}), AlertContext()), isTrue);
            expect(condition(TelemetryEvent('e', data: <String, Object?>{'n': 5}), AlertContext()), isFalse);
          case 'op->=':
            expect(condition(TelemetryEvent('e', data: <String, Object?>{'n': 5}), AlertContext()), isTrue);
          case 'op-<':
            expect(condition(TelemetryEvent('e', data: <String, Object?>{'n': 4}), AlertContext()), isTrue);
          case 'op-<=':
            expect(condition(TelemetryEvent('e', data: <String, Object?>{'n': 5}), AlertContext()), isTrue);
          case 'op-==':
            expect(condition(TelemetryEvent('e', data: <String, Object?>{'n': 5}), AlertContext()), isTrue);
          case 'op-!=':
            expect(condition(TelemetryEvent('e', data: <String, Object?>{'n': 6}), AlertContext()), isTrue);
        }
      }
    });

    test('未知严重级别退回 warning，未知运算符不触发', () {
      final List<AlertRule> rules = RuleParser.parse(<String, Object?>{
        'rules': <Object?>[
          <String, Object?>{
            'name': 'r',
            'severity': 'bogus',
            'condition': <String, Object?>{
              'event': 'e',
              'field': 'n',
              'operator': '~',
              'value': 5,
            },
          },
        ],
      });
      expect(rules.single.severity, AlertSeverity.warning);
      expect(rules.single.condition(TelemetryEvent('e', data: <String, Object?>{'n': 6}), AlertContext()), isFalse);
    });

    test('condition 缺失抛 ArgumentError', () {
      expect(
        () => RuleParser.parse(<String, Object?>{
          'rules': <Object?>[<String, Object?>{'name': 'r', 'severity': 'info'}],
        }),
        throwsArgumentError,
      );
    });
  });
}
