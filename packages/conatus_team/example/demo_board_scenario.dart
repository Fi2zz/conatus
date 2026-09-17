/// Demo 场景 3-4：任务板 DAG（经团队工具编排）与中途移除成员。
///
/// 场景 3 从「模型视角」驱动——通过 [ToolRegistry.call] 直接调
/// `spawn_teammate` / `team_task_create` / `team_task_update`，等价于
/// 模型下发工具调用，演示共享任务板如何用 DAG 依赖做同步点。
library;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_team/conatus_team.dart';

/// 场景 3：建两个有依赖的任务，观察 DAG 何时解锁。
Future<void> scenarioBoard(AgentTeam team, ToolRegistry tools) async {
  print('\n=== 场景 3：任务板 DAG（模型经团队工具编排）===');
  final String mateId = _idOf(await tools.call(const ToolCall(
    name: 'spawn_teammate',
    arguments: <String, Object?>{'name': '调研员'},
  )));
  final String survey = _idOf(await tools.call(ToolCall(
    name: 'team_task_create',
    arguments: <String, Object?>{
      'description': '调研竞品缓存方案',
      'assignee': mateId,
    },
  )));
  final String report = _idOf(await tools.call(ToolCall(
    name: 'team_task_create',
    arguments: <String, Object?>{
      'description': '基于调研写选型报告',
      'depends_on': <String>[survey],
    },
  )));
  print('· 建链：$survey（调研）→ $report（报告，依赖前者）');
  print('· 初始可领取：${_claimable(team, mateId)}');

  await _update(tools, survey, mateId, 'claimed');
  await _update(tools, survey, mateId, 'done', result: '调研完成');
  print('· 前序 done 后可领取：${_claimable(team, mateId)}');
}

/// 场景 4：用户中途改主意，移除某个成员。
Future<void> scenarioRemove(AgentTeam team, String name) async {
  print('\n=== 场景 4：中途调整（移除成员）===');
  final Teammate? target = _byName(team, name);
  if (target == null) {
    print('· 未找到成员「$name」');
    return;
  }
  await team.remove(target.id);
  final String rest = team.members.map((Teammate m) => m.name).join('、');
  print('· 已移除「${target.name}」，剩余成员：$rest');
  print('语音播报 > ${memberRemovedMessage(target.name)}');
}

Future<void> _update(
  ToolRegistry tools,
  String taskId,
  String mateId,
  String status, {
  String? result,
}) async {
  await tools.call(ToolCall(
    name: 'team_task_update',
    arguments: <String, Object?>{
      'task_id': taskId,
      'teammate_id': mateId,
      'status': status,
      if (result != null) 'result': result,
    },
  ));
}

String _idOf(ToolResult result) =>
    '${(result.value! as Map<String, Object?>)['id']}';

String _claimable(AgentTeam team, String mateId) {
  final List<String> ids = <String>[
    for (final TeamTask t in team.claimableBy(mateId)) t.id,
  ];
  return ids.isEmpty ? '（无）' : ids.join('、');
}

Teammate? _byName(AgentTeam team, String name) {
  for (final Teammate m in team.members) {
    if (m.name == name) return m;
  }
  return null;
}
