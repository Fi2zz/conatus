/// 团队协作服务端口与错误类型。
///
/// [AgentTeam] 是多智能体协作的底层机制：成员生命周期、消息系统、任务板。
/// 协作模式（顺序 / 并发 / 群聊 / Maker-Checker）是策略，复用同一套机制。
/// 任务板是唯一同步点——成员之间不直接读写彼此的状态，所有协调通过任务板
/// 进行（DAG 依赖 + CAS 乐观锁）。成员有独立的上下文窗口，只交换结论，
/// 不交换过程。
library;

import 'dart:async';

import 'team_events.dart';
import 'team_task.dart';
import 'teammate.dart';

/// Team 相关错误。
class TeamException implements Exception {
  const TeamException(this.code, this.message);

  /// 稳定的机器可读错误码（如 `version-mismatch` / `deps-not-met`）。
  final String code;

  /// 面向用户/模型的可读消息。
  final String message;

  @override
  String toString() => 'TeamException($code): $message';
}

/// 团队协作服务。
abstract class AgentTeam {
  /// 队长 ID。创建团队成员时用作 parentTaskId。
  String get leadId;

  /// 当前所有成员。
  List<Teammate> get members;

  /// 当前所有任务。
  List<TeamTask> get tasks;

  /// 创建成员（仅 Lead）。
  ///
  /// [tools] 是该成员可用的工具白名单。为空时继承 Lead 的非高危工具。
  Future<Teammate> spawn({
    required String name,
    List<String>? tools,
    String? systemPrompt,
  });

  /// 发送消息给指定成员。成员在下一轮工作时读到。
  Future<void> send(String teammateId, String message);

  /// 发送消息并等待本轮结束，返回成员回复。等价于 [send] + [wait] +
  /// 取 reply；面向协作模式（顺序 / 并发 / 群聊 / Maker-Checker）。
  Future<String> ask(String teammateId, String message);

  /// 等待指定成员完成当前工作。
  Future<Teammate> wait(String teammateId, {Duration? timeout});

  /// 等待所有成员完成。
  Future<List<Teammate>> waitAll({Duration? timeout});

  /// 中断指定成员。
  Future<void> interrupt(String teammateId);

  /// 移除指定成员（终态成员可移除）。
  Future<void> remove(String teammateId);

  /// 创建任务。依赖见 [dependsOn]，预分配见 [assigneeId]。
  Future<TeamTask> createTask({
    required String description,
    List<String> dependsOn = const <String>[],
    String? assigneeId,
  });

  /// 领取任务。依赖未全完成时抛 [TeamException]('deps-not-met')。
  /// 用 [version] 做 CAS 校验，版本不符抛 [TeamException]('version-mismatch')。
  Future<TeamTask> claimTask(
    String taskId,
    String teammateId, {
    int? version,
  });

  /// 完成任务。
  Future<TeamTask> completeTask(
    String taskId,
    String teammateId, {
    Object? result,
    int? version,
  });

  /// 释放任务（重新回到 pending）。
  Future<TeamTask> releaseTask(
    String taskId,
    String teammateId, {
    int? version,
  });

  /// 查询单个任务。
  TeamTask? task(String id);

  /// 可被指定成员领取的任务：状态 pending、依赖全 done、[assigneeId]
  /// 为 null 或等于该成员。
  List<TeamTask> claimableBy(String teammateId);

  /// 变更流。
  Stream<AgentTeamEvent> get changes;

  /// 释放资源。随上下文自动调用。
  void dispose();
}
