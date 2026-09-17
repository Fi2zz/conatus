/// 团队任务追踪 seam：把成员生命周期映射到外部任务系统（如 TaskCenter）。
///
/// conatus_team 不直接依赖 conatus_tasks，而是通过本抽象注入。装配方在
/// 主程序侧用 adapter 把 [TaskCenter] 适配成 [TeamTaskTracker]：
/// [beginMember] → `tasks.create(kind: TaskKind.subAgent, ...)`，
/// [completeMember] → `tasks.update(status: completed)`，
/// [failMember] → `tasks.update(status: failed)`。缺省 [noop] 不追踪。
library;

import 'dart:async';

/// 团队任务追踪端口。
abstract class TeamTaskTracker {
  /// 成员被创建时调用；返回外部任务 id（不追踪返回 null）。
  Future<String?> beginMember({
    required String teammateId,
    required String name,
    required String leadId,
  });

  /// 成员正常结束（done 或被 remove 时 idle / working）。
  Future<void> completeMember(String teammateId, {Object? result});

  /// 成员失败。
  Future<void> failMember(String teammateId, {Object? error});

  /// 不追踪的单例。
  static const TeamTaskTracker noop = _NoopTeamTaskTracker();
}

class _NoopTeamTaskTracker implements TeamTaskTracker {
  const _NoopTeamTaskTracker();

  @override
  Future<String?> beginMember({
    required String teammateId,
    required String name,
    required String leadId,
  }) async => null;

  @override
  Future<void> completeMember(String teammateId, {Object? result}) async {}

  @override
  Future<void> failMember(String teammateId, {Object? error}) async {}
}
