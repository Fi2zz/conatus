/// 权限判定的作用域：规则列表 + 兜底阈值 + 归属 Agent。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import 'permission_rule.dart';

/// 一次工具调用要对照的权限上下文。
///
/// [rules] 的顺序即优先级，**调用方**负责按 `config → project → session` 拼好，
/// 引擎不再排序（后出现的规则覆盖先出现的规则）。
///
/// [askThreshold] 是「没有任何规则命中」时的兜底阈值：
/// - `null`：兜底全放行（等价于免审批）；
/// - `ToolRisk.medium` / `ToolRisk.high`：达到该风险等级才询问用户。
///
/// [agentId] 标记作用域归属的 Agent（主 Agent 缺省 `build`），供调用方展示与
/// 多 Agent 场景区分；判定逻辑本身不读它。
class PermissionScope {
  /// 创建作用域。
  const PermissionScope({
    this.rules = const <PermissionRule>[],
    this.askThreshold,
    this.agentId = 'build',
  });

  /// 已按优先级排好的规则列表。
  final List<PermissionRule> rules;

  /// 无规则命中时的兜底询问阈值；`null` 表示全部放行。
  final ToolRisk? askThreshold;

  /// 作用域归属的 Agent 标识。
  final String agentId;
}
