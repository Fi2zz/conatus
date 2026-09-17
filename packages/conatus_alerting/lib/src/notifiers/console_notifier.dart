/// 控制台通知：stderr 一行一条。
library;

import 'dart:io';

import '../alert.dart';
import 'notifier.dart';

/// 控制台通知。
class ConsoleNotifier implements AlertNotifier {
  /// 构造。[writer] 缺省 [stderr]。
  ConsoleNotifier({this.writer, this.showTime = true});

  /// 输出目标。
  final IOSink? writer;

  /// 是否带时间戳前缀。
  final bool showTime;

  @override
  String get name => 'console';

  @override
  Future<void> notify(Alert alert) async {
    final IOSink sink = writer ?? stderr;
    final String prefix =
        showTime ? '[${alert.firedAt.toIso8601String()}] ' : '';
    final String marker = switch (alert.severity) {
      AlertSeverity.info => '[INFO]',
      AlertSeverity.warning => '[WARN]',
      AlertSeverity.critical => '[CRIT]',
    };
    sink.writeln('$prefix$marker ${alert.rule}: ${alert.summary}');
  }

  @override
  void dispose() {}
}
