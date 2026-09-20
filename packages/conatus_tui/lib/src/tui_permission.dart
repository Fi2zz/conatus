/// TUI 权限模式：三档审批强度，决定哪些工具在执行前需要用户确认。
///
/// 模式只影响审批阈值（[TuiPermissionMode.threshold]），与工具自身声明的
/// [ToolRisk] 对应：Always Ask 连有副作用的操作（medium 起）都要问，
/// Ask When Needed 只问高危（high），Never Ask 完全不拦。
///
/// 模式以 `permission/mode` 事件持久化到 [Session]（append-only，折叠最后一条），
/// 因此**按会话生效**：切回某个会话即恢复它自己的模式。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

/// 权限模式变更事件类型。
const String kPermissionModeEvent = 'permission/mode';

/// 权限模式。
enum TuiPermissionMode {
  /// 只读自动放行，其余都要确认。
  alwaysAsk,

  /// 常规改动自动执行，高危操作仍需确认。
  askWhenNeeded,

  /// 不打断：所有操作直接执行。
  neverAsk;

  /// 审批阈值；[neverAsk] 为 `null`（不装审批中间件）。
  ToolRisk? get threshold => switch (this) {
        TuiPermissionMode.alwaysAsk => ToolRisk.medium,
        TuiPermissionMode.askWhenNeeded => ToolRisk.high,
        TuiPermissionMode.neverAsk => null,
      };

  /// 选项名。
  String get label => switch (this) {
        TuiPermissionMode.alwaysAsk => '始终询问',
        TuiPermissionMode.askWhenNeeded => '按需询问',
        TuiPermissionMode.neverAsk => '从不询问',
      };

  /// 选项说明。
  String get description => switch (this) {
        TuiPermissionMode.alwaysAsk => '只读操作自动放行，其余都要你先批准。',
        TuiPermissionMode.askWhenNeeded => '常规改动与命令自动执行，高危操作仍会询问。',
        TuiPermissionMode.neverAsk => '不打断你：所有操作自动执行并自行决定。',
      };
}

/// 解析模式标识；无法识别返回 `null`。
TuiPermissionMode? parsePermissionMode(String raw) {
  final String key = raw.trim().toLowerCase();
  for (final TuiPermissionMode mode in TuiPermissionMode.values) {
    if (mode.name.toLowerCase() == key) {
      return mode;
    }
  }
  return null;
}

/// 折叠会话自身后缀里最后一个 `permission/mode` 事件，还原该会话的权限模式。
///
/// 无记录时返回 [TuiPermissionMode.askWhenNeeded]（默认档）。只折叠
/// [Session.ownEvents]：fork 出的会话不继承父会话的模式。
TuiPermissionMode restorePermissionMode(Session session) {
  for (final SessionEvent event in session.ownEvents.reversed) {
    if (event.type != kPermissionModeEvent) continue;
    final Object? data = event.data;
    if (data is Map) {
      final TuiPermissionMode? mode = parsePermissionMode('${data['mode']}');
      if (mode != null) {
        return mode;
      }
    }
    return TuiPermissionMode.askWhenNeeded;
  }
  return TuiPermissionMode.askWhenNeeded;
}
