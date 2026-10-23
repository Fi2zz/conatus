/// 当前会话 / Agent 的权限作用域槽位。
///
/// 权限中间件只在根上下文挂**一次**（见 `instrumentPermission`），会话切换、
/// 权限模式切换、子 Agent 换档都只替换槽位里的 [PermissionScope]；中间件每次
/// 调用都读 `current`，因此无需重挂。
library;

import 'permission_rule.dart';
import 'permission_scope.dart';

/// 槽位在上下文里的服务键。
const String kPermissionScopeService = 'permissionScope';

/// 可替换的 [PermissionScope] 持有者。
class PermissionScopeSlot {
  /// 以 [initial] 作为初始作用域（缺省全放行）。
  PermissionScopeSlot([this._current = const PermissionScope()]);

  PermissionScope _current;

  /// 当前作用域。
  PermissionScope get current => _current;

  /// 整体替换作用域。
  void set(PermissionScope scope) {
    _current = scope;
  }

  /// 追加一条规则（保留阈值与 Agent 标识）。
  void addRule(PermissionRule rule) {
    _current = PermissionScope(
      rules: <PermissionRule>[..._current.rules, rule],
      askThreshold: _current.askThreshold,
      agentId: _current.agentId,
    );
  }
}
