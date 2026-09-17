import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_alerting/conatus_alerting.dart';
import 'package:test/test.dart';

import 'support/recording_notifier.dart';

void main() {
  group('QuietHoursNotifier', () {
    late DateTime now;
    late RecordingNotifier inner;
    late QuietHoursNotifier notifier;

    setUp(() {
      now = DateTime(2026, 9, 17, 23);
      inner = RecordingNotifier();
      notifier = QuietHoursNotifier(
        inner: inner,
        quietStart: 22,
        quietEnd: 7,
        now: () => now,
      );
    });

    Alert sample(AlertSeverity severity) => Alert(
          id: 'a1',
          rule: 'llm-slow',
          severity: severity,
          event: TelemetryEvent('llm.request'),
          firedAt: DateTime(2026),
        );

    test('静默期内非 critical 只记录不播报', () async {
      await notifier.notify(sample(AlertSeverity.warning));
      expect(inner.alerts, isEmpty);
    });

    test('静默期内 critical 放行', () async {
      await notifier.notify(sample(AlertSeverity.critical));
      expect(inner.alerts, hasLength(1));
    });

    test('非静默时间放行', () async {
      now = DateTime(2026, 9, 17, 12);
      await notifier.notify(sample(AlertSeverity.warning));
      expect(inner.alerts, hasLength(1));
    });

    test('跨越午夜的静默期（22:00–07:00）', () async {
      // 早晨 6 点仍在静默期
      now = DateTime(2026, 9, 18, 6);
      await notifier.notify(sample(AlertSeverity.warning));
      expect(inner.alerts, isEmpty);

      // 早晨 8 点解除
      now = DateTime(2026, 9, 18, 8);
      await notifier.notify(sample(AlertSeverity.warning));
      expect(inner.alerts, hasLength(1));
    });
  });
}
