import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_alerting/conatus_alerting.dart';
import 'package:test/test.dart';

void main() {
  group('ConsoleNotifier', () {
    Alert sample() => Alert(
          id: 'a1',
          rule: 'llm-slow',
          severity: AlertSeverity.warning,
          event: TelemetryEvent('llm.request'),
          firedAt: DateTime(2026, 9, 17, 10, 30),
        );

    Future<String> capture(void Function(IOSink sink) run) async {
      final Directory dir = await Directory.systemTemp.createTemp('conatus_alerting');
      addTearDown(() => dir.delete(recursive: true));
      final IOSink sink = File('${dir.path}/out.txt').openWrite();
      run(sink);
      await sink.close();
      return File('${dir.path}/out.txt').readAsString();
    }

    test('输出带时间戳与标记的告警行', () async {
      final String out = await capture((IOSink sink) =>
          ConsoleNotifier(writer: sink).notify(sample()));

      expect(out, contains('[WARN] llm-slow:'));
      expect(out, contains('2026-09-17T10:30'));
    });

    test('showTime=false 时不带时间戳', () async {
      final String out = await capture((IOSink sink) =>
          ConsoleNotifier(writer: sink, showTime: false).notify(sample()));

      expect(out, startsWith('[WARN]'));
      expect(out, isNot(contains('2026-09-17')));
    });

    test('severity 标记映射', () async {
      final String out = await capture((IOSink sink) => ConsoleNotifier(
            writer: sink,
            showTime: false,
          ).notify(Alert(
            id: 'a',
            rule: 'r',
            severity: AlertSeverity.critical,
            event: TelemetryEvent('e'),
            firedAt: DateTime(2026),
          )));

      expect(out, startsWith('[CRIT]'));
    });
  });
}
