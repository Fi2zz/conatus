/// 运行状态词汇：运行与节点的状态机。
///
/// [RunStatus] 描述一次流程执行的总体状态（含终态判断），
/// [RunNodeStatus] 描述单个节点的执行状态。两者独立演进：
/// 运行级 `running` 期间，各节点可处于 pending / ready / running /
/// completed / skipped / failed。
library;

/// 运行状态。
enum RunStatus {
  /// 已创建，未开始。
  pending,

  /// 执行中。
  running,

  /// 暂停。
  paused,

  /// 完成（终态）。
  completed,

  /// 失败（终态）。
  failed,

  /// 取消（终态）。
  cancelled,
}

/// 节点运行状态。
enum RunNodeStatus {
  /// 等待依赖。
  pending,

  /// 可执行。
  ready,

  /// 执行中。
  running,

  /// 完成（终态）。
  completed,

  /// 跳过（条件不满足）。
  skipped,

  /// 失败（终态）。
  failed,
}
