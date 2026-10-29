/// 权限规则模型。
library;

import 'permission_effect.dart';

/// 一条 `<action, resource> -> effect` 规则。
///
/// [action] 是工具动作标识（如 `bash` / `edit` / `read`），按**精确值**匹配；
/// [resource] 是通配 pattern（见 `permissionPatternMatches`）。命中同一动作的
/// 多条规则时**最后一条生效**，因此规则列表的先后顺序就是优先级。
class PermissionRule {
  /// 创建规则。
  const PermissionRule({
    required this.action,
    required this.resource,
    required this.effect,
    this.source,
    this.configuredResource,
  });

  /// 动作标识，精确匹配。
  final String action;

  /// 资源通配 pattern（可能已按 workdir / 真实路径展开）。
  final String resource;

  /// 命中后的处置。
  final PermissionEffect effect;

  /// 规则来源标记（如 `config` / `project` / `session`），仅用于展示与排查。
  final String? source;

  /// 用户在配置里写的原始 pattern；展开后的规则用它上屏，避免审批框显示
  /// `/private/var/...` 这类内部拼写。
  final String? configuredResource;

  /// 展示用 pattern：优先原始配置，其次匹配用 pattern。
  String get displayResource => configuredResource ?? resource;

  @override
  String toString() =>
      'PermissionRule($action, $displayResource, ${effect.name})'
      '${source == null ? '' : ' @$source'}';
}
