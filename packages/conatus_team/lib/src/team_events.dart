/// 团队事件：[AgentTeam] 状态变更的不可变记录。
///
/// 通过 [AgentTeam.changes] 流出。事件按子类区分变更种类；调用方按
/// `switch` 模式匹配分发。所有事件都是不可变值对象。
library;

import 'team_task.dart';
import 'teammate.dart';

/// 团队事件基类（sealed：子类固定，便于穷尽匹配）。
sealed class AgentTeamEvent {
  const AgentTeamEvent();
}

/// 新成员被创建（[AgentTeam.spawn] 成功）。
class TeammateSpawned extends AgentTeamEvent {
  const TeammateSpawned(this.teammate);
  final Teammate teammate;
}

/// 成员状态变更（idle / working / waiting / finished / done / failed）。
class TeammateStatusChanged extends AgentTeamEvent {
  const TeammateStatusChanged(this.teammate);
  final Teammate teammate;
}

/// 新任务被创建（[AgentTeam.createTask] 成功）。
class TeamTaskCreated extends AgentTeamEvent {
  const TeamTaskCreated(this.task);
  final TeamTask task;
}

/// 任务被领取 / 完成 / 失败 / 释放。
class TeamTaskChanged extends AgentTeamEvent {
  const TeamTaskChanged(this.task);
  final TeamTask task;
}

/// 一条直达消息被发出（[AgentTeam.send] 成功）。
class TeamMessageSent extends AgentTeamEvent {
  const TeamMessageSent(this.from, this.to, this.message);
  final String from;
  final String to;
  final String message;
}
