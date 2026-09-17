/// 观测面板：把团队 / 任务板 / 任务中心 / 会话 / 遥测的最终状态打出来。
///
/// 这五项分别对应 [AgentTeam] 的四条 seam（任务追踪 / 会话 / 审批 /
/// 遥测）加上任务板本身——demo 的收尾快照。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_tasks/conatus_tasks.dart';
import 'package:conatus_team/conatus_team.dart';

/// 打印一次全量观测面板。
void printReport({
  required AgentTeam team,
  required TaskCenter tasks,
  required Session session,
  required InMemoryTelemetry telemetry,
}) {
  print('\n=== 观测面板 ===');
  _printMembers(team);
  _printBoard(team);
  _printTaskCenter(tasks);
  print('· 队长会话：团队事件 ${_ownTeamEvents(session)} 条 / 总事件 ${session.length} 条');
  print('· 遥测 team.* 事件：${_telemetryNames(telemetry).join(', ')}');
}

void _printMembers(AgentTeam team) {
  final String names = team.members
      .map((Teammate m) => '${m.name}(${m.status.name})')
      .join(' / ');
  print('· 成员：$names');
}

void _printBoard(AgentTeam team) {
  print('· 任务板：');
  for (final TeamTask t in team.tasks) {
    final String deps =
        t.dependsOn.isEmpty ? '' : ' ← ${t.dependsOn.join(', ')}';
    print('  - ${t.id} ${t.status.name} ${t.description}$deps');
  }
}

void _printTaskCenter(TaskCenter tasks) {
  print('· TaskCenter 任务树（映射成员生命周期，移除成员时落定）：');
  for (final Task t in tasks.all) {
    print('  - ${t.kind.name} ${t.status.name} ${t.description}');
  }
}

int _ownTeamEvents(Session session) => session.ownEvents
    .where((SessionEvent e) => e.type.startsWith('team/'))
    .length;

List<String> _telemetryNames(InMemoryTelemetry telemetry) {
  final Set<String> names = <String>{
    for (final TelemetryEvent e in telemetry.recent)
      if (e.name.startsWith('team.')) e.name,
  };
  return names.toList()..sort();
}
