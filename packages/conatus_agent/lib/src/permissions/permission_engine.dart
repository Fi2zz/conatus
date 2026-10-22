/// 权限引擎：把作用域规则折叠成一次判定。
///
/// 判定分两层：
/// 1. 对每个 resource 取**最后一条**命中规则（见 [lastMatchingRule]）；
/// 2. 多资源聚合：任一 `deny` → deny，否则任一 `ask` → ask，否则任一 `allow`
///    → allow。完全无命中才回退 [PermissionScope.askThreshold]。
///
/// 因此显式规则总能压过兜底阈值：`askThreshold: null` 不会被规则里的 deny
/// 绕过，显式 allow 也不会被高风险阈值抬成 ask。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import 'permission_effect.dart';
import 'permission_matcher.dart';
import 'permission_rule.dart';
import 'permission_scope.dart';
import 'permission_verdict.dart';

/// 无状态判定器；可安全复用同一实例。
class PermissionEngine {
  /// 创建引擎。
  const PermissionEngine();

  /// 判定一次 `action` + [resources] 调用。
  ///
  /// [risk] 只在没有任何规则命中时参与兜底。返回的
  /// [PermissionVerdict.rule] 是决定结果的规则：deny / ask 取对应级别的
  /// 最后一条；纯 allow 取最后一条 allow；兜底判定为 `null`。
  PermissionVerdict evaluate({
    required String action,
    required List<String> resources,
    required ToolRisk risk,
    required PermissionScope scope,
  }) {
    PermissionRule? deny;
    PermissionRule? ask;
    PermissionRule? allow;
    for (final String resource in resources) {
      final PermissionRule? rule =
          lastMatchingRule(scope.rules, action, resource);
      if (rule == null) continue;
      switch (rule.effect) {
        case PermissionEffect.deny:
          deny = rule;
        case PermissionEffect.ask:
          ask = rule;
        case PermissionEffect.allow:
          allow = rule;
      }
    }
    final PermissionRule? deciding = deny ?? ask ?? allow;
    return PermissionVerdict(
      effect: deciding?.effect ?? _fallbackEffect(risk, scope.askThreshold),
      action: action,
      resources: resources,
      rule: deciding,
    );
  }

  /// 无规则命中时的兜底：阈值缺省全放行，否则按风险等级比较。
  PermissionEffect _fallbackEffect(ToolRisk risk, ToolRisk? threshold) {
    if (threshold == null) return PermissionEffect.allow;
    return risk.index >= threshold.index
        ? PermissionEffect.ask
        : PermissionEffect.allow;
  }
}
