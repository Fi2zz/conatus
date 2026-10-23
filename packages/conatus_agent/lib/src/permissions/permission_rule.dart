/// 权限规则模型。
library;

import 'permission_effect.dart';

/// 一条 `<action, resource> -> effect` 规则。
///
/// [action] 是工具动作标识（如 `shell` / `edit` / `read`），按**精确值**匹配；
/// [resource] 是通配 pattern（见 `permissionPatternMatches`）。命中同一动作的
/// 多条规则时**最后一条生效**，因此规则列表的先后顺序就是优先级。
class PermissionRule {
  /// 创建规则。
  const PermissionRule({
    required this.action,
    required this.resource,
    required this.effect,
    this.source,
  });

  /// 动作标识，精确匹配。
  final String action;

  /// 资源通配 pattern。
  final String resource;

  /// 命中后的处置。
  final PermissionEffect effect;

  /// 规则来源标记（如 `config` / `project` / `session`），仅用于展示与排查。
  final String? source;

  @override
  String toString() => 'PermissionRule($action, $resource, ${effect.name})'
      '${source == null ? '' : ' @$source'}';
}
