/// `ctx.tools.group(...)` 与能力分级。
///
/// [ToolGroups.group] 按领域一次性注册一组工具；[ToolGroups.guardRisk] 依据
/// [Tool.riskLevel] 在调用前拒绝越级工具（能力分级）；[ToolGroups.describeWithin]
/// 只投影某一等级内的工具 schema。分组登记与注册表状态分离（`Expando` 按注册表
/// 实例存放），不改动 [ToolRegistry] 本体。
///
/// ```dart
/// ctx.tools.group('web', <Tool>[WebSearchTool(...), FetchUrlTool(...)]);
/// ctx.tools.guardRisk(ToolRisk.low); // 只放行 low
/// ```
library;

import 'package:conatus_core/conatus_core.dart';
import 'tools.dart';

final Expando<Map<String, String>> _assigned = Expando<Map<String, String>>();

/// 工具分组与风险分级的扩展。
extension ToolGroups on ToolRegistry {
  /// 按领域注册一组工具；返回撤销函数（幂等，撤销整组）。
  ///
  /// 同组内重复名或与既有工具重名抛 [StateError]（与 [ToolRegistry.register]
  /// 同一口径）。
  Disposer group(String name, List<Tool> tools) {
    final Map<String, String> assigned = _assigned[this] ??= <String, String>{};
    final List<Disposer> disposers = <Disposer>[];
    for (final Tool tool in tools) {
      disposers.add(register(tool));
      assigned[tool.name] = name;
    }
    bool done = false;
    return () {
      if (done) return;
      done = true;
      for (final Disposer off in disposers.reversed) {
        off();
      }
      for (final Tool tool in tools) {
        assigned.remove(tool.name);
      }
    };
  }

  /// 已登记的分组名（首次出现的顺序）。
  List<String> get groups {
    final Map<String, String>? assigned = _assigned[this];
    if (assigned == null) return const <String>[];
    final List<String> result = <String>[];
    for (final String group in assigned.values) {
      if (!result.contains(group)) result.add(group);
    }
    return result;
  }

  /// 某工具的分组：注册时登记的优先，否则回退到 [Tool.group]。
  String? groupOf(String name) => _assigned[this]?[name] ?? get(name)?.group;

  /// 某分组下的工具名（注册顺序）。
  List<String> namesIn(String group) => <String>[
        for (final String name in names)
          if (groupOf(name) == group) name,
      ];

  /// 某分组下工具的模型 schema。
  List<Map<String, Object?>> describeGroup(String group) =>
      <Map<String, Object?>>[
        for (final String name in namesIn(group)) get(name)!.toSchema(),
      ];

  /// 只投影风险等级不高于 [maxRisk] 的工具 schema。
  List<Map<String, Object?>> describeWithin(ToolRisk maxRisk) =>
      <Map<String, Object?>>[
        for (final String name in names)
          if (get(name)!.riskLevel.index <= maxRisk.index)
            get(name)!.toSchema(),
      ];

  /// 能力分级守卫：拒绝风险等级高于 [maxRisk] 的工具调用。
  ///
  /// 返回撤销函数（幂等）。
  Disposer guardRisk(ToolRisk maxRisk) => guard((ToolCall call) {
        final Tool? tool = get(call.name);
        if (tool != null && tool.riskLevel.index > maxRisk.index) {
          return '工具 "${call.name}" 风险等级 ${tool.riskLevel.name} '
              '高于允许的 ${maxRisk.name}';
        }
        return null;
      });
}
