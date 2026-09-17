/// 团队状态快照与 TUI 视图模式。
///
/// [TeamSnapshot] 是 UI 渲染的数据源：由 [TeamSubscription] 事件驱动重建，
/// 渲染组件只读它，不直接触达 [AgentTeam]。视图模式 [ViewMode] 表示
/// 对话视图（默认）与团队视图之间的切换。
library;

import 'package:conatus_team/conatus_team.dart';

/// 团队状态快照。UI 渲染的数据源。
class TeamSnapshot {
  const TeamSnapshot({
    this.members = const <Teammate>[],
    this.tasks = const <TeamTask>[],
    this.totalCost = 0.0,
  });

  /// 所有成员。
  final List<Teammate> members;

  /// 所有任务。
  final List<TeamTask> tasks;

  /// 累计成本。
  final double totalCost;

  /// 活跃成员数（非终态）。
  int get activeMembers => members.where((m) => !m.isTerminal).length;

  /// 已完成任务数。
  int get doneTasks =>
      tasks.where((t) => t.status == TeamTaskStatus.done).length;

  /// 任务总数。
  int get totalTasks => tasks.length;

  /// 是否有活跃团队。
  bool get hasTeam => members.isNotEmpty;

  /// 可被指定成员领取的任务：pending、依赖全 done、[assigneeId] 为空或等于该成员。
  List<TeamTask> claimableBy(String teammateId) {
    final Set<String> doneIds = tasks
        .where((TeamTask t) => t.status == TeamTaskStatus.done)
        .map((TeamTask t) => t.id)
        .toSet();
    return tasks.where((TeamTask t) {
      if (t.status != TeamTaskStatus.pending) return false;
      if (t.assigneeId != null && t.assigneeId != teammateId) return false;
      return t.dependsOn.every(doneIds.contains);
    }).toList();
  }
}

/// TUI 视图模式。
enum ViewMode {
  /// 对话视图（默认）。
  chat,

  /// 团队视图。
  team,
}
