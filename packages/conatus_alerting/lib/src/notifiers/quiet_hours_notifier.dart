/// 静默期通知：静默期内只记录，critical 例外。
library;

import 'dart:io';

import '../alert.dart';
import 'notifier.dart';

/// 静默期通知装饰器。
///
/// 静默期内非 [AlertSeverity.critical] 告警只记录到 stderr，不播报；
/// critical 始终放行。静默期跨越午夜时用 `quietStart > quietEnd` 表达。
class QuietHoursNotifier implements AlertNotifier {
  /// 构造。[inner] 是被装饰的渠道。
  QuietHoursNotifier({
    required this.inner,
    required this.quietStart,
    required this.quietEnd,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AlertNotifier inner;

  /// 静默开始小时（如 22 表示晚上 10 点）。
  final int quietStart;

  /// 静默结束小时（如 7 表示早上 7 点）。
  final int quietEnd;

  final DateTime Function() _now;

  @override
  String get name => 'quiet-hours';

  @override
  Future<void> notify(Alert alert) async {
    final int hour = _now().hour;
    final bool isQuiet = quietStart > quietEnd
        ? hour >= quietStart || hour < quietEnd
        : hour >= quietStart && hour < quietEnd;

    if (isQuiet && alert.severity != AlertSeverity.critical) {
      stderr.writeln('[quiet] ${alert.summary}');
      return;
    }
    await inner.notify(alert);
  }

  @override
  void dispose() => inner.dispose();
}
