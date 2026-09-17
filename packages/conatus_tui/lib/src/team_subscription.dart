/// 团队订阅：把 [AgentTeam.changes] 事件流折叠成 [TeamSnapshot]，通知 UI 重绘。
///
/// UI 订阅而非轮询（HANDOFF-12 设计原则）：任何团队变更都走同一入口重建
/// 快照，渲染组件只读快照。成本为可选 seam——未注入 [TeamCostSource] 时
/// 快照成本恒为 0，由渲染侧决定是否展示。
library;

import 'dart:async';

import 'package:conatus_team/conatus_team.dart';

import 'team_snapshot.dart';

/// 团队成本来源（可选 seam）。
///
/// 当前 conatus_observability 尚无成本追踪实现，此接口保留注入点：
/// 未来宿主提供 `totalCost` 后，状态栏即可显示成本。
abstract class TeamCostSource {
  /// 累计成本。
  double get totalCost;
}

/// 团队订阅。维护 [TeamSnapshot] 并通知 UI 重绘。
class TeamSubscription {
  TeamSubscription({
    required this.team,
    required this.onChanged,
    this.costSource,
  }) {
    _snapshot = _buildSnapshot();
    _subscription = team.changes.listen(_handleEvent);
  }

  /// 被订阅的团队。
  final AgentTeam team;

  /// 快照变化回调（UI 据此重绘）。
  final void Function(TeamSnapshot) onChanged;

  /// 成本来源；缺省不提供成本。
  final TeamCostSource? costSource;

  late TeamSnapshot _snapshot;
  StreamSubscription<AgentTeamEvent>? _subscription;

  /// 最新快照。
  TeamSnapshot get snapshot => _snapshot;

  void _handleEvent(AgentTeamEvent event) {
    if (event is TeamMessageSent) return; // 消息是内部通信，不驱动 UI。
    _snapshot = _buildSnapshot();
    onChanged(_snapshot);
  }

  TeamSnapshot _buildSnapshot() {
    return TeamSnapshot(
      members: List<Teammate>.unmodifiable(team.members),
      tasks: List<TeamTask>.unmodifiable(team.tasks),
      totalCost: costSource?.totalCost ?? 0.0,
    );
  }

  /// 释放订阅（幂等）。
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
