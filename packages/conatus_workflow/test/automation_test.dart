import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_alerting/conatus_alerting.dart';
import 'package:conatus_workflow/conatus_workflow.dart';
import 'package:test/test.dart';

void main() {
  group('Trigger 子类', () {
    test('CronTrigger 保存表达式', () {
      const trigger = CronTrigger('0 9 * * *');
      expect(trigger, isA<Trigger>());
      expect(trigger.expression, '0 9 * * *');
    });

    test('EventTrigger 保存事件名与过滤器', () {
      const trigger = EventTrigger('tool.called');
      expect(trigger.eventName, 'tool.called');
      expect(trigger.filter, isNull);
    });

    test('EventTrigger 可带过滤器', () {
      const trigger = EventTrigger('tool.called', filter: _wantsOk);
      expect(trigger.filter, isNotNull);
    });

    test('ConditionTrigger 保存规则', () {
      const rule = AlertRule(
        name: 'high-cost',
        severity: AlertSeverity.warning,
        condition: _never,
      );
      const trigger = ConditionTrigger(rule);
      expect(trigger.rule.name, 'high-cost');
      expect(trigger.rule.severity, AlertSeverity.warning);
    });

    test('ManualTrigger 无字段', () {
      expect(const ManualTrigger(), isA<Trigger>());
    });
  });

  group('Automation', () {
    test('缺省值：空输入、空约束、无后处理、无冷却', () {
      const automation = Automation(
        name: 'nightly-backup',
        trigger: ManualTrigger(),
        workflowName: 'backup',
      );
      expect(automation.inputs, isEmpty);
      expect(automation.constraints, isEmpty);
      expect(automation.onComplete, isNull);
      expect(automation.cooldown, Duration.zero);
    });
  });
}

bool _wantsOk(TelemetryEvent event) => true;
bool _never(TelemetryEvent event, AlertContext ctx) => false;
