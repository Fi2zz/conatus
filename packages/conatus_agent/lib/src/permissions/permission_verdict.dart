/// 权限判定结果。
library;

import 'permission_effect.dart';
import 'permission_rule.dart';

/// 一次权限判定的完整结果：效果、命中的规则、被判定的一对动作与资源。
///
/// [rule] 为 `null` 表示没有规则命中（结果来自兜底策略），此时 [effect] 由
/// 调用方给出的阈值决定。
class PermissionVerdict {
  /// 创建判定结果。
  const PermissionVerdict({
    required this.effect,
    required this.action,
    required this.resources,
    this.rule,
  });

  /// 最终处置。
  final PermissionEffect effect;

  /// 命中的规则；无命中为 `null`。
  final PermissionRule? rule;

  /// 被判定的动作标识。
  final String action;

  /// 被判定的资源列表（一次调用可能携带多个路径/命令）。
  final List<String> resources;

  @override
  String toString() => 'PermissionVerdict($action, $resources, ${effect.name})';
}
