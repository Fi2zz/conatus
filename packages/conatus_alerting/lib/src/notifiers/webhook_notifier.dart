/// Webhook 通知：Slack 兼容的 JSON 负载。
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../alert.dart';
import 'notifier.dart';

/// Webhook 通知。
///
/// 发送 Slack 兼容负载（`text` + `attachments`）。失败只记录到 stderr，
/// 不抛异常。[client] 可注入 Mock（`package:http/testing.dart` 的
/// [http.MockClient] 是范例）。
class WebhookNotifier implements AlertNotifier {
  /// 构造。
  WebhookNotifier({
    required this.url,
    this.headers = const <String, String>{},
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  /// 目标地址。
  final Uri url;

  /// 附加请求头。
  final Map<String, String> headers;

  final http.Client _client;

  /// 单次请求超时。
  final Duration timeout;

  @override
  String get name => 'webhook';

  @override
  Future<void> notify(Alert alert) async {
    final String marker = switch (alert.severity) {
      AlertSeverity.info => 'INFO',
      AlertSeverity.warning => 'WARN',
      AlertSeverity.critical => 'CRIT',
    };
    final Map<String, Object?> body = <String, Object?>{
      'text': '[$marker] ${alert.rule}: ${alert.summary}',
      'attachments': <Object?>[
        <String, Object?>{
          'color': _colorOf(alert.severity),
          'fields': <Object?>[
            <String, Object?>{'title': '规则', 'value': alert.rule, 'short': true},
            <String, Object?>{
              'title': '严重级别',
              'value': alert.severity.name,
              'short': true,
            },
            <String, Object?>{'title': '事件', 'value': alert.event.name, 'short': true},
          ],
        },
      ],
    };
    try {
      await _client
          .post(
            url,
            headers: <String, String>{'Content-Type': 'application/json', ...headers},
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } catch (error) {
      stderr.writeln('[webhook] 通知失败: $error');
    }
  }

  @override
  void dispose() => _client.close();

  static String _colorOf(AlertSeverity severity) => switch (severity) {
        AlertSeverity.info => 'good',
        AlertSeverity.warning => 'warning',
        AlertSeverity.critical => 'danger',
      };
}
