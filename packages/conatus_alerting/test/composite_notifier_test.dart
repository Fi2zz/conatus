import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_alerting/conatus_alerting.dart';
import 'package:test/test.dart';

import 'support/recording_notifier.dart';

void main() {
  group('CompositeNotifier', () {
    Alert sample() => Alert(
          id: 'a1',
          rule: 'llm-slow',
          severity: AlertSeverity.warning,
          event: TelemetryEvent('llm.request'),
          firedAt: DateTime(2026),
        );

    test('并行通知全部渠道', () async {
      final RecordingNotifier first = RecordingNotifier();
      final RecordingNotifier second = RecordingNotifier();
      final CompositeNotifier notifier =
          CompositeNotifier(<AlertNotifier>[first, second]);

      await notifier.notify(sample());

      expect(first.alerts, hasLength(1));
      expect(second.alerts, hasLength(1));
    });

    test('单个渠道失败不影响其他', () async {
      final RecordingNotifier failing = RecordingNotifier()
        ..notifyError = StateError('down');
      final RecordingNotifier healthy = RecordingNotifier();
      final CompositeNotifier notifier =
          CompositeNotifier(<AlertNotifier>[failing, healthy]);

      await notifier.notify(sample());

      expect(healthy.alerts, hasLength(1));
    });

    test('dispose 级联各渠道', () {
      final RecordingNotifier first = RecordingNotifier();
      final RecordingNotifier second = RecordingNotifier();
      final CompositeNotifier notifier =
          CompositeNotifier(<AlertNotifier>[first, second]);

      notifier.dispose();
      expect(first.disposed, isTrue);
      expect(second.disposed, isTrue);
    });
  });
}
