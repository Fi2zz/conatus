/// 团队语音播报：订阅 [AgentTeam.changes]，把进展摘要经 TTS 播报出去。
///
/// 播报是摘要而非逐条列出（HANDOFF-12 §9）：成员完成 / 失败、任务完成时
/// 播报一句话，且经 [minInterval] 节流避免轰炸。音频输出目标由宿主注入
/// [TtsAudioSink]（扬声器 / 文件 / 网络），缺省 no-op——桌面 TUI 无声，
/// 智能音箱宿主传入 sink 即启用。
library;

import 'dart:async';

import 'package:conatus_team/conatus_team.dart';
import 'package:conatus_tts/conatus_tts.dart';

import 'team_snapshot.dart';

/// 语音播报器。订阅团队事件，用 TTS 播报进度。
class VoiceReporter {
  VoiceReporter({
    required this.team,
    required this.tts,
    this.sink,
    this.enabled = true,
    this.minInterval = const Duration(seconds: 5),
  }) {
    if (enabled) {
      _subscription = team.changes.listen(_handleEvent);
    }
  }

  /// 被播报的团队。
  final AgentTeam team;

  /// TTS 服务。
  final TtsService tts;

  /// 音频输出目标；缺省 no-op。
  final TtsAudioSink? sink;

  /// 是否启用播报。
  final bool enabled;

  /// 播报最小间隔（节流）。
  final Duration minInterval;

  static final TtsAudioSink _noopSink = CallbackAudioSink(onData: (_) {});

  StreamSubscription<AgentTeamEvent>? _subscription;
  DateTime? _lastReport;

  void _handleEvent(AgentTeamEvent event) {
    final String? message = _messageFor(event);
    if (message == null) return;
    final DateTime now = DateTime.now();
    if (_lastReport != null && now.difference(_lastReport!) < minInterval) {
      return;
    }
    unawaited(_report(message));
  }

  String? _messageFor(AgentTeamEvent event) {
    return switch (event) {
      TeammateStatusChanged(:final teammate) => switch (teammate.status) {
          TeammateStatus.done => '${teammate.name} 完成了',
          TeammateStatus.failed => '${teammate.name} 失败了',
          _ => null,
        },
      TeamTaskChanged(:final task) => task.status == TeamTaskStatus.done
          ? '任务「${task.description}」完成了'
          : null,
      _ => null,
    };
  }

  Future<void> _report(String message) async {
    _lastReport = DateTime.now();
    try {
      await tts.speak(message, sink ?? _noopSink);
    } catch (error) {
      // 播报失败不阻塞团队运行。
    }
  }

  /// 释放订阅（幂等）。
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}

/// 生成团队进度摘要（被动查询 / 状态展示共用）。
String summarizeTeamProgress(TeamSnapshot snapshot) {
  if (!snapshot.hasTeam) {
    return '现在没有正在进行的团队任务。';
  }
  final List<Teammate> members = snapshot.members;
  final List<Teammate> done = <Teammate>[
    for (final Teammate m in members)
      if (m.status == TeammateStatus.done ||
          m.status == TeammateStatus.finished)
        m,
  ];
  final List<Teammate> working = <Teammate>[
    for (final Teammate m in members)
      if (m.status == TeammateStatus.working) m,
  ];
  final List<Teammate> waiting = <Teammate>[
    for (final Teammate m in members)
      if (m.status == TeammateStatus.waiting) m,
  ];
  final List<Teammate> failed = <Teammate>[
    for (final Teammate m in members)
      if (m.status == TeammateStatus.failed) m,
  ];
  final List<String> parts = <String>[
    if (done.isNotEmpty) '${done.map((Teammate m) => m.name).join('、')}完成了',
    if (working.isNotEmpty)
      '${working.map((Teammate m) => m.name).join('、')}还在进行',
    if (waiting.isNotEmpty)
      '${waiting.map((Teammate m) => m.name).join('、')}在等待',
    if (failed.isNotEmpty) '${failed.map((Teammate m) => m.name).join('、')}失败了',
  ];
  final String header = '${snapshot.doneTasks}/${snapshot.totalTasks} 个任务完成。';
  if (parts.isEmpty) return header;
  return '$header${parts.join('，')}。';
}
