/// 团队渲染件：状态栏、成员卡片、任务行与团队视图。
///
/// 所有组件只读 [TeamSnapshot]，不触达 [AgentTeam]——状态来自订阅流，
/// 交互走斜杠命令。图标约定见 HANDOFF-12 §7.2 / §8.2 / §8.3（成员状态
/// 实际 6 态，`finished` 用 `●`、终态 `done` 用 `✓` 区分）。
library;

import 'package:conatus_team/conatus_team.dart';
import 'package:nocterm/nocterm.dart';

import 'team_snapshot.dart';

/// 成员状态图标与文案。
(String, String) memberStatusDisplay(TeammateStatus status) {
  return switch (status) {
    TeammateStatus.idle => ('○', '空闲'),
    TeammateStatus.working => ('◐', '执行中'),
    TeammateStatus.waiting => ('◌', '等待'),
    TeammateStatus.finished => ('●', '完成'),
    TeammateStatus.done => ('✓', '已完成'),
    TeammateStatus.failed => ('✗', '失败'),
  };
}

/// 任务状态图标与文案。
(String, String) taskStatusDisplay(TeamTaskStatus status) {
  return switch (status) {
    TeamTaskStatus.pending => ('○', '待领取'),
    TeamTaskStatus.claimed => ('◐', '执行中'),
    TeamTaskStatus.done => ('✓', '完成'),
    TeamTaskStatus.failed => ('✗', '失败'),
  };
}

/// 团队状态栏。单行，显示团队概况；无团队时不渲染。
class TeamStatusBar extends StatelessComponent {
  const TeamStatusBar({
    super.key,
    required this.snapshot,
    this.showCost = false,
  });

  /// 团队快照。
  final TeamSnapshot snapshot;

  /// 是否显示成本（有成本来源时开启）。
  final bool showCost;

  @override
  Component build(BuildContext context) {
    if (!snapshot.hasTeam) {
      return const SizedBox.shrink();
    }
    final List<String> parts = <String>[
      '团队: ${snapshot.activeMembers} 成员',
      '任务: ${snapshot.doneTasks}/${snapshot.totalTasks} 完成',
      if (showCost) '成本: \$${snapshot.totalCost.toStringAsFixed(2)}',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: const BoxDecoration(
        color: Color.fromRGB(0, 20, 40),
        border: BoxBorder(top: BorderSide(color: Colors.cyan)),
      ),
      child: Row(
        children: <Component>[
          Expanded(
            child: Text(
              ' ${parts.join(' | ')}',
              style: const TextStyle(color: Colors.gray),
            ),
          ),
        ],
      ),
    );
  }
}

/// 成员卡片：图标 + 名字 + 状态，当前任务与等待原因作为缩进行。
class MemberCard extends StatelessComponent {
  const MemberCard({super.key, required this.member, required this.tasks});

  /// 成员。
  final Teammate member;

  /// 团队任务（查当前任务描述）。
  final List<TeamTask> tasks;

  @override
  Component build(BuildContext context) {
    final (String icon, String statusText) = memberStatusDisplay(member.status);
    final TeamTask? currentTask = member.currentTaskId == null
        ? null
        : tasks.where((TeamTask t) => t.id == member.currentTaskId).firstOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Component>[
          Text('$icon ${member.name}  [$statusText]'),
          if (currentTask != null)
            Text(
              '  任务: ${currentTask.description}',
              style: const TextStyle(color: Colors.gray),
            ),
          if (member.status == TeammateStatus.waiting)
            const Text(
              '  等待依赖完成',
              style: TextStyle(color: Colors.gray),
            ),
        ],
      ),
    );
  }
}

/// 任务行：图标 + 描述 + 状态，负责人与依赖作为缩进行。
class TaskRow extends StatelessComponent {
  const TaskRow({super.key, required this.task, required this.members});

  /// 任务。
  final TeamTask task;

  /// 团队成员（查负责人名字）。
  final List<Teammate> members;

  @override
  Component build(BuildContext context) {
    final (String icon, String statusText) = taskStatusDisplay(task.status);
    final Teammate? assignee = task.assigneeId == null
        ? null
        : members.where((Teammate m) => m.id == task.assigneeId).firstOrNull;
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Component>[
          Text('$icon ${task.description}  [$statusText]'),
          if (assignee != null)
            Text(
              '  负责: ${assignee.name}',
              style: const TextStyle(color: Colors.gray),
            ),
          if (task.dependsOn.isNotEmpty &&
              task.status == TeamTaskStatus.pending)
            Text(
              '  依赖: ${task.dependsOn.join(', ')}',
              style: const TextStyle(color: Colors.gray),
            ),
        ],
      ),
    );
  }
}

/// 团队视图：成员列表 + 任务板，按需滚动。
class TeamView extends StatelessComponent {
  const TeamView({super.key, required this.snapshot});

  /// 团队快照。
  final TeamSnapshot snapshot;

  @override
  Component build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Component>[
          const Text(
            '团队视图（按 Ctrl+T 返回对话）',
            style: TextStyle(color: Colors.cyan),
          ),
          const SizedBox(height: 1),
          const Text(
            '成员',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          for (final Teammate member in snapshot.members)
            MemberCard(member: member, tasks: snapshot.tasks),
          const SizedBox(height: 1),
          const Text(
            '任务板',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          for (final TeamTask task in snapshot.tasks)
            TaskRow(task: task, members: snapshot.members),
        ],
      ),
    );
  }
}
