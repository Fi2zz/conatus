/// Demo 场景 1-2：并发三视角审查、Maker-Checker 修订循环。
///
/// 两个场景都只依赖 [AgentTeam] 机制 + 一个 [TeamPattern] 策略，演示
/// 「机制一套、模式多种」。场景 1 顺带订阅 [AgentTeam.changes]，展示
/// 事件流。
library;

import 'dart:async';

import 'package:conatus_team/conatus_team.dart';

/// 场景 1：三个成员并发审查同一份输入。
Future<void> scenarioConcurrent(AgentTeam team) async {
  print('\n=== 场景 1：并发三视角审查 ===');
  final List<String> events = <String>[];
  String midFlight = '';
  final StreamSubscription<AgentTeamEvent> sub = team.changes.listen(
    (AgentTeamEvent e) {
      events.add(_describe(e));
      if (midFlight.isEmpty && _anyWorking(team)) {
        midFlight = progressMessage(team);
      }
    },
  );
  final Object? replies = await const ConcurrentPattern().execute(
    team: team,
    input: '审查支付回调这段代码',
    options: <String, Object?>{'members': <String>['性能', '安全', '产品']},
  );
  await sub.cancel();

  for (final Object? reply in replies as List<Object?>) {
    print('· $reply');
  }
  print('事件流（前 6 条）：${events.take(6).join(' | ')}');
  print('语音播报：');
  print('  创建 > ${teamCreatedMessage(team.members)}');
  print('  进度 > ${midFlight.isEmpty ? '（未捕捉到执行中快照）' : midFlight}');
}

bool _anyWorking(AgentTeam team) =>
    team.members.any((Teammate m) => m.status == TeammateStatus.working);

/// 场景 2：Maker 提案 → Checker 审查 → 按反馈修订，直到通过。
Future<void> scenarioMakerChecker(AgentTeam team) async {
  print('\n=== 场景 2：Maker-Checker 修订循环 ===');
  final Object? proposal = await const MakerCheckerPattern().execute(
    team: team,
    input: '设计支付热点缓存方案',
    options: <String, Object?>{
      'maker': '提案人',
      'checker': '审查者',
      'maxIterations': 3,
    },
  );
  print('最终提案 > $proposal');
}

/// 把事件压成一行，便于在控制台观察事件流。
String _describe(AgentTeamEvent event) => switch (event) {
      TeammateSpawned(:final Teammate teammate) => 'spawn(${teammate.name})',
      TeammateStatusChanged(:final Teammate teammate) =>
        '${teammate.name}→${teammate.status.name}',
      TeamTaskCreated(:final TeamTask task) => 'task+(${task.id})',
      TeamTaskChanged(:final TeamTask task) =>
        'task~(${task.id}:${task.status.name})',
      TeamMessageSent(:final String to) => 'msg→$to',
    };