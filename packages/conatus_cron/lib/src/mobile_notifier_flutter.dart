// REASON: 本文件仅在 Flutter 环境（dart.library.ui 存在）经 `cron_notify.dart`
// 的条件导出编译；依赖 Flutter SDK 的 package:flutter/services，纯 Dart 的
// analyze 解析不了，故在包级 analysis_options.yaml 中排除分析。

import 'dart:async';

import 'package:flutter/services.dart';

import 'cron_notify.dart' show CronNotifier;

/// 经 [channel] 命名的 MethodChannel 构建通知端口。
///
/// 原生壳注册同名通道并实现 `notify` 调用，参数为
/// `{'title': String, 'body': String}`（iOS 用 UNUserNotificationCenter，
/// Android 用 NotificationManager）。通知是 best-effort：通道缺失或原生侧
/// 未实现时静默忽略，绝不影响调度。
CronNotifier buildMobileCronNotifier(String channel) {
  final MethodChannel port = MethodChannel(channel);
  return (String title, String body) {
    unawaited(
      port.invokeMethod<void>(
        'notify',
        <String, String>{'title': title, 'body': body},
      ).catchError((Object _) {}),
    );
  };
}
