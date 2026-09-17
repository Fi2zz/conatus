/// 语音通知：TTS 播报，或降级为文本提问（askUser）。
library;

import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_tts/conatus_tts.dart';

import '../alert.dart';
import 'notifier.dart';

/// 语音通知（智能音箱场景）。
///
/// 组合 `askUser` / `tts` seam：有 TTS 与音频 [sink] 时播报口语化消息，
/// 否则降级为 [AskUser.ask] 文本提问。用户口头响应经 [onUserAccepted] /
/// [onUserRejected] 触发后续动作。通知失败只记录到 stderr，不抛异常。
class AskUserNotifier implements AlertNotifier {
  /// 构造。
  AskUserNotifier({
    required this.askUser,
    this.tts,
    this.sink,
    this.voicePrefix = '',
    this.onUserAccepted,
    this.onUserRejected,
    this.yesWords = const <String>{'y', 'yes', '是', '好', '继续', '换一个', '可以'},
    this.noWords = const <String>{'n', 'no', '否', '不要', '停止', '不行'},
  });

  /// 提问器（文本降级通道）。
  final AskUser askUser;

  /// TTS 服务（可选）。
  final TtsService? tts;

  /// 音频输出（可选；提供时 TTS 才播报）。
  final TtsAudioSink? sink;

  /// 文本提问的前缀（如「告警：」）。
  final String voicePrefix;

  /// 用户同意时的回调。
  final void Function(Alert alert)? onUserAccepted;

  /// 用户拒绝时的回调。
  final void Function(Alert alert)? onUserRejected;

  /// 视为「是」的回答（小写比较）。
  final Set<String> yesWords;

  /// 视为「否」的回答（小写比较）。
  final Set<String> noWords;

  @override
  String get name => 'ask-user';

  @override
  Future<void> notify(Alert alert) async {
    final String message = _humanReadable(alert);
    final TtsService? tts = this.tts;
    final TtsAudioSink? sink = this.sink;
    if (tts != null && sink != null) {
      try {
        await tts.speak(message, sink);
        return;
      } catch (error) {
        stderr.writeln('[ask-user] TTS 播报失败: $error');
      }
    }
    try {
      final String response = await askUser.ask('$voicePrefix$message');
      final String normalized = response.trim().toLowerCase();
      if (yesWords.contains(normalized)) {
        onUserAccepted?.call(alert);
      } else if (noWords.contains(normalized)) {
        onUserRejected?.call(alert);
      }
    } catch (error) {
      stderr.writeln('[ask-user] 提问失败: $error');
    }
  }

  /// 把告警转成口语化的句子。
  String _humanReadable(Alert alert) {
    switch (alert.rule) {
      case 'llm-slow':
        return '这个操作有点慢，我还在等。';
      case 'tool-failures':
        return '这个任务试了几次都不行，要换个方法吗？';
      case 'session-budget':
        return '今天的用量有点多，要继续吗？';
      case 'agent-loop':
        return '这个任务比较复杂，需要更多步骤，继续吗？';
      case 'subagent-stuck':
        return '有个子任务卡住了，要我中断它吗？';
      default:
        return alert.summary;
    }
  }

  @override
  void dispose() {}
}
