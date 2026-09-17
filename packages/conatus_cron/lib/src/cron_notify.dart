/// 系统通知端口：任务运行结束时的原生 OS 通知。
///
/// 平台矩阵：macOS 走 `osascript`（可带 Glass 音效），Linux 走 `notify-send`，
/// Windows / iOS / Android 没有可 exec 的系统命令，[systemCronNotifier] 在
/// 这些平台返回 null——由宿主注入 [CronNotifier]（端口形态本就是可选注入）。
///
/// iOS / Android 走 [mobileCronNotifier]：Flutter 环境自动经 MethodChannel
/// `conatus/cron` 投递 `notify` 调用（参数 `{'title', 'body'}`），原生壳实现
/// UNUserNotificationCenter / NotificationManager 即可；也可用任意
/// [CronNotifier] 实现（如 flutter_local_notifications）自行注入。
///
/// 通知是 best-effort：5 秒超时、绝不抛错、不阻塞调度器。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'mobile_notifier_stub.dart'
    if (dart.library.ui) 'mobile_notifier_flutter.dart';

/// 系统通知端口：收到标题与正文，投递方式由实现决定。
typedef CronNotifier = void Function(String title, String body);

/// 系统命令超时。
const Duration _notifyTimeout = Duration(seconds: 5);

/// 返回系统原生通知端口；当前平台不支持（非 macOS / Linux）时返回 null。
CronNotifier? systemCronNotifier({bool sound = true}) {
  if (Platform.isMacOS) return _macNotifier(sound);
  if (Platform.isLinux) return _linuxNotifier;
  return null;
}

/// 移动端（iOS / Android）通知端口。
///
/// Flutter 环境（`dart.library.ui` 存在）经 [channel] 命名的 MethodChannel 向
/// 原生壳投递 `notify` 调用（参数 `{'title', 'body'}`；iOS 用
/// UNUserNotificationCenter、Android 用 NotificationManager）；纯 Dart 环境
/// 没有 MethodChannel，返回 null，请注入 [CronNotifier] 或改用 Flutter 构建。
CronNotifier? mobileCronNotifier({String channel = 'conatus/cron'}) =>
    buildMobileCronNotifier(channel);

CronNotifier _macNotifier(bool sound) => (String title, String body) {
      final String text = _squash(body);
      final String script = 'display notification ${jsonEncode(text)} '
          'with title ${jsonEncode(title)}'
          '${sound ? ' sound name "Glass"' : ''}';
      _dispatch('osascript', <String>['-e', script]);
    };

void _linuxNotifier(String title, String body) =>
    _dispatch('notify-send', <String>[title, _squash(body)]);

/// 正文压成单行并截断到 200 字符（与 dsh-cron 一致）。
String _squash(String body) {
  final String squashed = body.replaceAll(RegExp(r'\s+'), ' ');
  return squashed.length <= 200 ? squashed : squashed.substring(0, 200);
}

void _dispatch(String command, List<String> args) {
  try {
    final Future<ProcessResult> run = Process.run(command, args);
    unawaited(run
        .timeout(
          _notifyTimeout,
          onTimeout: () => ProcessResult(-1, -1, '', 'notify timeout'),
        )
        .catchError((Object _) => ProcessResult(-1, -1, '', 'notify failed')));
  } on Object {
    // best effort only：通知失败不影响调度。
  }
}
