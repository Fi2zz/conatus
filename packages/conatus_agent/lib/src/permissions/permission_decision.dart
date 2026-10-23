/// 权限中间件一次判定的完整输入与结论。
library;

import 'permission_effect.dart';
import 'permission_verdict.dart';

/// 判定结论：最终处置 + 动作 / 资源 / 路径 + 原始 verdict。
///
/// 只在权限中间件内部流转（不从包入口导出），因此字段直接暴露。
class PermissionDecision {
  /// 创建判定结论。
  const PermissionDecision({
    required this.effect,
    required this.action,
    required this.resources,
    required this.pathArgs,
    required this.verdict,
    this.fallback = false,
  });

  /// 最终处置（可能被路径兜底抬成 ask）。
  final PermissionEffect effect;

  /// 权限动作。
  final String action;

  /// 被判定资源。
  final List<String> resources;

  /// 工具声明的路径参数取值。
  final List<String> pathArgs;

  /// 引擎原始判定。
  final PermissionVerdict verdict;

  /// 结论来自兜底阈值（不是显式规则）。
  final bool fallback;
}
