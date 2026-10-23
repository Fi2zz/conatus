/// 权限规则的效果。
library;

/// 一条权限规则命中后对工具调用的处置。
enum PermissionEffect {
  /// 直接放行，不弹审批。
  allow,

  /// 交给人确认（审批链）。
  ask,

  /// 直接拒绝，连审批机会都不给。
  deny,
}
