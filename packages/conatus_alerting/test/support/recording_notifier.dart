/// 测试共用的记录型通知渠道与 Mock AskUser。
library;

import 'package:conatus_alerting/conatus_alerting.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

/// 记录收到的告警，便于断言。
class RecordingNotifier implements AlertNotifier {
  /// 收到的告警（按顺序）。
  final List<Alert> alerts = <Alert>[];

  /// 非空时 [notify] 抛它（模拟通知失败）。
  Object? notifyError;

  /// 是否被 dispose。
  bool disposed = false;

  @override
  String get name => 'recording';

  @override
  Future<void> notify(Alert alert) async {
    final Object? error = notifyError;
    if (error != null) throw error;
    alerts.add(alert);
  }

  @override
  void dispose() {
    disposed = true;
  }
}

/// 可脚本化回答的 AskUser。
class MockAskUser implements AskUser {
  MockAskUser(this.answer);

  /// 预设的回答。
  String answer;

  /// 收到的提问。
  final List<String> prompts = <String>[];

  /// 是否被 cancel。
  bool cancelled = false;

  @override
  Future<String> ask(String prompt) async {
    prompts.add(prompt);
    return answer;
  }

  @override
  void cancel() {
    cancelled = true;
  }
}
