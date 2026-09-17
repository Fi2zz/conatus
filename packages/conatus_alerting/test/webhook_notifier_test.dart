import 'dart:convert';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_alerting/conatus_alerting.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('WebhookNotifier', () {
    Alert sample() => Alert(
          id: 'a1',
          rule: 'llm-slow',
          severity: AlertSeverity.warning,
          event: TelemetryEvent('llm.request'),
          firedAt: DateTime(2026, 9, 17, 10, 30),
        );

    test('发送 Slack 兼容负载', () async {
      late http.Request captured;
      final MockClient client = MockClient((http.Request request) async {
        captured = request;
        return http.Response('ok', 200);
      });
      final WebhookNotifier notifier = WebhookNotifier(
        url: Uri.parse('https://hooks.example.com/abc'),
        client: client,
      );

      await notifier.notify(sample());

      expect(captured.method, 'POST');
      expect(captured.url.toString(), 'https://hooks.example.com/abc');
      expect(captured.headers['Content-Type'], 'application/json');
      final Map<String, Object?> body =
          jsonDecode(captured.body) as Map<String, Object?>;
      expect(body['text'], contains('[WARN] llm-slow:'));
      final List<Object?> attachments = body['attachments'] as List<Object?>;
      expect(attachments, hasLength(1));
      expect((attachments.single as Map)['color'], 'warning');
      notifier.dispose();
    });

    test('携带附加请求头', () async {
      late http.Request captured;
      final MockClient client = MockClient((http.Request request) async {
        captured = request;
        return http.Response('ok', 200);
      });
      final WebhookNotifier notifier = WebhookNotifier(
        url: Uri.parse('https://hooks.example.com/abc'),
        headers: <String, String>{'X-Token': 'secret'},
        client: client,
      );

      await notifier.notify(sample());
      expect(captured.headers['X-Token'], 'secret');
      notifier.dispose();
    });

    test('通知失败只记录不抛异常', () async {
      final MockClient failing = MockClient(
          (http.Request request) async => throw http.ClientException('down'));
      final WebhookNotifier notifier = WebhookNotifier(
        url: Uri.parse('https://hooks.example.com/abc'),
        client: failing,
      );

      await notifier.notify(sample()); // 不抛
      notifier.dispose();
    });
  });
}
