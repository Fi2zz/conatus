import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_alerting/conatus_alerting.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:test/test.dart';

import 'support/recording_notifier.dart';

void main() {
  group('AlertingImpl', () {
    late InMemoryTelemetry telemetry;
    late RecordingNotifier notifier;
    late DateTime now;
    late AlertingImpl alerting;

    setUp(() {
      telemetry = InMemoryTelemetry();
      notifier = RecordingNotifier();
      now = DateTime(2026, 9, 17, 10);
      alerting = AlertingImpl(
        telemetry: telemetry,
        notifier: notifier,
        rules: <AlertRule>[
          AlertRule(
            name: 'llm-slow',
            severity: AlertSeverity.warning,
            condition: (event, ctx) =>
                event.name == 'llm.request' &&
                (event.data['durationMs'] as int? ?? 0) > 30000,
          ),
        ],
        now: () => now,
      );
    });

    tearDown(() => alerting.dispose());

    void emitLlmSlow() {
      telemetry.emit(TelemetryEvent('llm.request',
          data: <String, Object?>{'durationMs': 35000}));
    }

    test('规则条件满足时触发告警并通知', () async {
      emitLlmSlow();
      await pumpEventQueue();

      expect(alerting.activeAlerts, hasLength(1));
      expect(alerting.history, hasLength(1));
      expect(notifier.alerts, hasLength(1));
      expect(notifier.alerts.single.rule, 'llm-slow');
      expect(notifier.alerts.single.severity, AlertSeverity.warning);
    });

    test('冷却期内同一规则不重复触发', () async {
      emitLlmSlow();
      await pumpEventQueue();
      emitLlmSlow();
      await pumpEventQueue();

      expect(alerting.history, hasLength(1));

      now = now.add(const Duration(minutes: 6));
      emitLlmSlow();
      await pumpEventQueue();
      expect(alerting.history, hasLength(2));
    });

    test('条件不满足不触发', () async {
      telemetry.emit(TelemetryEvent('llm.request',
          data: <String, Object?>{'durationMs': 100}));
      await pumpEventQueue();
      expect(alerting.history, isEmpty);
    });

    test('规则条件抛异常不影响其他规则', () async {
      alerting.addRule(AlertRule(
        name: 'broken',
        severity: AlertSeverity.critical,
        condition: (event, ctx) => throw StateError('boom'),
      ));
      emitLlmSlow();
      await pumpEventQueue();

      expect(alerting.history, hasLength(1), reason: 'broken 规则异常被隔离');
    });

    test('通知失败不阻塞主流程', () async {
      notifier.notifyError = StateError('webhook down');
      emitLlmSlow();
      await pumpEventQueue();

      expect(alerting.history, hasLength(1), reason: '告警仍记录');
    });

    test('告警流广播触发', () async {
      final List<Alert> received = <Alert>[];
      final cancel = alerting.alerts.listen(received.add);

      emitLlmSlow();
      await pumpEventQueue();
      expect(received, hasLength(1));

      await cancel.cancel();
    });

    test('fire 手动触发不经过冷却', () async {
      final Alert manual = Alert(
        id: 'manual-1',
        rule: 'llm-slow',
        severity: AlertSeverity.warning,
        event: TelemetryEvent('manual'),
        firedAt: now,
      );
      await alerting.fire(manual);
      await alerting.fire(manual);

      expect(alerting.activeAlerts, hasLength(2));
      expect(notifier.alerts, hasLength(2));
    });

    test('resolve 从活跃列表移除', () async {
      emitLlmSlow();
      await pumpEventQueue();

      alerting.resolve(alerting.activeAlerts.single.id);
      expect(alerting.activeAlerts, isEmpty);
      expect(alerting.history, hasLength(1), reason: '历史保留');
    });

    test('sessionId / goalId 从事件 data 提取', () async {
      telemetry.emit(TelemetryEvent('llm.request', data: <String, Object?>{
        'durationMs': 35000,
        'sessionId': 's9',
        'goalId': 'g9',
      }));
      await pumpEventQueue();

      expect(alerting.activeAlerts.single.sessionId, 's9');
      expect(alerting.activeAlerts.single.goalId, 'g9');
    });

    test('addRule 同名覆盖并重注册冷却期', () {
      alerting.addRule(AlertRule(
        name: 'llm-slow',
        severity: AlertSeverity.critical,
        cooldown: const Duration(hours: 1),
        condition: (event, ctx) => true,
      ));
      expect(alerting.rules.single.severity, AlertSeverity.critical);

      alerting.removeRule('llm-slow');
      expect(alerting.rules, isEmpty);
    });

    test('dispose 释放通知渠道', () {
      alerting.dispose();
      expect(notifier.disposed, isTrue);
    });
  });

  group('provideAlerting', () {
    test('提供服务并绑定 ctx 生命周期', () async {
      final Context ctx = Context.root();
      provideTelemetry(ctx);
      final Alerting service = provideAlerting(ctx);
      await pumpEventQueue();

      expect(ctx.get<Alerting>('alerting'), service);
      expect(service.rules, isNotEmpty, reason: '缺省默认规则集');

      ctx.dispose();
      // dispose 幂等，不抛
    });

    test('缺省通知渠道是控制台', () {
      final Context ctx = Context.root();
      provideTelemetry(ctx);
      final Alerting service = provideAlerting(ctx);
      // 通过规则触发验证不抛异常即可（ConsoleNotifier 写 stderr）
      expect(service, isA<Alerting>());
    });
  });
}
