/// 检查点的装配选项：启用开关、保留点数、后端选择与排除策略。
library;

import 'checkpoint_policy.dart';

/// 快照后端。
enum CheckpointBackend {
  /// 有 git 用影子 git，否则退回归档。
  auto,

  /// 影子 git 仓库（内容寻址 + 增量）。
  git,

  /// 自研 gzip 归档（零外部依赖）。
  archive,
}

/// 检查点的装配选项。
///
/// 取代产品侧的配置类型：`CheckpointManager` 只读 [enabled]；[keep] /
/// [backend] / [policy] 供打开存储的工厂使用。
class CheckpointOptions {
  const CheckpointOptions({
    this.enabled = true,
    this.keep = 5,
    this.backend = CheckpointBackend.auto,
    this.policy = const CheckpointPolicy(),
  });

  /// 是否启用检查点（关闭时不落盘、不恢复）。
  final bool enabled;

  /// 回滚点数（含基线）；`<= 0` 不限制。
  final int keep;

  /// 后端选择。
  final CheckpointBackend backend;

  /// 排除与只读策略。
  final CheckpointPolicy policy;
}
