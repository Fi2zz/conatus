/// 复合通知：多个渠道并行发送。
library;

import 'dart:io';

import '../alert.dart';
import 'notifier.dart';

/// 复合通知：并行调用多个渠道，任一失败只记录到 stderr。
class CompositeNotifier implements AlertNotifier {
  /// 构造。
  CompositeNotifier(this.notifiers);

  /// 渠道列表。
  final List<AlertNotifier> notifiers;

  @override
  String get name => 'composite';

  @override
  Future<void> notify(Alert alert) async {
    await Future.wait(notifiers.map((AlertNotifier n) =>
        n.notify(alert).catchError((Object error) {
      stderr.writeln('[${n.name}] 通知失败: $error');
    })));
  }

  @override
  void dispose() {
    for (final AlertNotifier n in notifiers) {
      n.dispose();
    }
  }
}
