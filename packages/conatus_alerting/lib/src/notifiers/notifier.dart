/// 告警通知渠道（Capability Seam）。
library;

import '../alert.dart';

/// 告警通知渠道。
///
/// 通知失败应记录到 stderr，**不抛异常**（告警不阻塞主流程）。
abstract class AlertNotifier {
  /// 通知渠道名字。
  String get name;

  /// 发送告警。
  Future<void> notify(Alert alert);

  /// 释放资源（默认无操作）。幂等。
  void dispose() {}
}
