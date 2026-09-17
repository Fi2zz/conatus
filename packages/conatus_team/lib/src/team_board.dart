/// 任务板：DAG 依赖与 CAS 乐观锁的纯内存实现。
///
/// [AgentTeam] 的任务操作委托给这里。状态变更有 CAS 校验：调用方传期望
/// [TeamTask.version]，实现层校验通过后递增。DAG 依赖在 claim 时检查，
/// 未全 done 时抛 [TeamException]('deps-not-met')。
library;

import 'agent_team.dart' show TeamException;
import 'team_task.dart';

/// [AgentTeam] 的任务板：内存 + CAS + DAG。
class TeamBoard {
  final List<TeamTask> _tasks = <TeamTask>[];
  int _seq = 0;

  /// 当前所有任务（按创建顺序）。
  List<TeamTask> get all => List<TeamTask>.unmodifiable(_tasks);

  /// 新建任务；version 0、status pending。
  TeamTask create({
    required String description,
    List<String> dependsOn = const <String>[],
    String? assigneeId,
  }) {
    _seq++;
    final TeamTask task = TeamTask(
      id: 'team-task-$_seq',
      description: description,
      status: TeamTaskStatus.pending,
      dependsOn: List<String>.unmodifiable(dependsOn),
      version: 0,
      createdAt: DateTime.now(),
      assigneeId: assigneeId,
    );
    _tasks.add(task);
    return task;
  }

  /// 按 ID 查任务；不存在返回 null。
  TeamTask? get(String id) {
    for (final TeamTask t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// 可被 [teammateId] 领取的任务：pending、依赖全 done、assignee 兼容。
  List<TeamTask> claimableBy(String teammateId) {
    final Set<String> doneIds = _doneIds();
    return _tasks
        .where((TeamTask t) =>
            t.status == TeamTaskStatus.pending &&
            (t.assigneeId == null || t.assigneeId == teammateId) &&
            t.dependsOn.every(doneIds.contains))
        .toList(growable: false);
  }

  /// 领取任务；CAS + 依赖 + assignee 兼容性检查。
  TeamTask claim(String taskId, String teammateId, {int? version}) {
    final TeamTask task = _require(taskId);
    _assertState(task, TeamTaskStatus.pending, 'claim');
    if (task.assigneeId != null && task.assigneeId != teammateId) {
      throw TeamException(
          'assigned-to-other', '任务 "$taskId" 不属于 $teammateId');
    }
    _assertDeps(task, _doneIds());
    _checkVersion(task, version);
    return _replace(
      task,
      task.copyWith(
        status: TeamTaskStatus.claimed,
        assigneeId: teammateId,
        version: task.version + 1,
      ),
    );
  }

  /// 完成任务。
  TeamTask complete(String taskId, String teammateId,
      {Object? result, int? version}) {
    final TeamTask task = _require(taskId);
    _assertState(task, TeamTaskStatus.claimed, 'complete');
    _assertAssignee(task, teammateId);
    _checkVersion(task, version);
    return _replace(
      task,
      task.copyWith(
        status: TeamTaskStatus.done,
        result: result,
        version: task.version + 1,
      ),
    );
  }

  /// 释放任务（回 pending，清空 assignee）。
  TeamTask release(String taskId, String teammateId, {int? version}) {
    final TeamTask task = _require(taskId);
    _assertState(task, TeamTaskStatus.claimed, 'release');
    _assertAssignee(task, teammateId);
    _checkVersion(task, version);
    return _replace(
      task,
      task.copyWith(
        status: TeamTaskStatus.pending,
        assigneeId: null,
        version: task.version + 1,
      ),
    );
  }

  Set<String> _doneIds() => <String>{
        for (final TeamTask t in _tasks)
          if (t.status == TeamTaskStatus.done) t.id,
      };

  TeamTask _require(String id) {
    final TeamTask? t = get(id);
    if (t == null) {
      throw TeamException('not-found', '任务 "$id" 不存在');
    }
    return t;
  }

  void _assertState(TeamTask task, TeamTaskStatus expected, String action) {
    if (task.status != expected) {
      throw TeamException(
          'bad-state', '任务 "${task.id}" 状态为 ${task.status.name}，不能 $action');
    }
  }

  void _assertAssignee(TeamTask task, String teammateId) {
    if (task.assigneeId != teammateId) {
      throw TeamException(
          'assignee-mismatch', '任务 "${task.id}" 不属于 $teammateId');
    }
  }

  void _assertDeps(TeamTask task, Set<String> doneIds) {
    final List<String> unmet = <String>[
      for (final String dep in task.dependsOn)
        if (!doneIds.contains(dep)) dep,
    ];
    if (unmet.isNotEmpty) {
      throw TeamException(
          'deps-not-met', '任务 "${task.id}" 依赖未完成：${unmet.join(', ')}');
    }
  }

  void _checkVersion(TeamTask task, int? expected) {
    if (expected != null && expected != task.version) {
      throw TeamException(
          'version-mismatch', '任务 "${task.id}" 版本 ${task.version}，期望 $expected');
    }
  }

  TeamTask _replace(TeamTask old, TeamTask updated) {
    final int i = _tasks.indexOf(old);
    _tasks[i] = updated;
    return updated;
  }
}
