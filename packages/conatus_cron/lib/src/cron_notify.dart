/// 系统通知端口：任务运行结束时的原生 OS 通知。
///
/// macOS 走 `osascript`（可带 Glass 音效），Linux 走 `notify-send`；其他平台
/// 返回 null（安静的 no-op）。通知是 best-effort：5 秒超时、绝不抛错、不阻塞
/// 调度器。端口形态为可选注入——宿主也可换成自己的实现（如桌面 UI 通知）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    unawaited(run.timeout(
      _notifyTimeout,
      onTimeout: () => ProcessResult(-1, -1, '', 'notify timeout'),
    ).catchError((Object _) => ProcessResult(-1, -1, '', 'notify failed')));
  } on Object {
    // best effort only：通知失败不影响调度。
  }
}
