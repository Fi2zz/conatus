/// 工具名 → 权限动作 / 资源的映射。
///
/// 动作是规则匹配的左边（`PermissionRule.action`），必须**精确**：命名类工具
/// 归一到稳定的动作名（`run_command` / `run_tests` / `run_code` / 后台命令都
/// 是 `shell`；`rg` 是 `grep`；联网工具是 `websearch` / `webfetch`），MCP 工具
/// `server__tool` 归一为 `server_tool`；其余工具直接用工具名，新增工具无需改
/// 映射也能被规则命中。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

/// 具名工具的动作归一表。
const Map<String, String> _actionAliases = <String, String>{
  'rg': 'grep',
  'run_command': 'shell',
  'run_tests': 'shell',
  'run_code': 'shell',
  'run_command_background': 'shell',
  'web_search': 'websearch',
  'fetch_url': 'webfetch',
};

/// MCP 工具名里的 server / tool 分隔符。
const String _mcpSeparator = '__';

/// 取 [toolName] 的权限动作。
String permissionActionFor(String toolName) {
  if (toolName.contains(_mcpSeparator)) {
    return toolName.replaceAll(_mcpSeparator, '_');
  }
  return _actionAliases[toolName] ?? toolName;
}

/// 取一次调用的权限资源列表。
///
/// 路径工具用声明的路径参数；shell 用命令串；联网工具用 URL / 查询词；其余
/// 用通配 `*`。空值同样落回 `*`，避免规则里出现匹配不到的空串。
List<String> permissionResourcesFor(
  ToolCall call,
  List<String> pathArgs,
) {
  if (pathArgs.isNotEmpty) return pathArgs;
  final String? value = switch (permissionActionFor(call.name)) {
    'shell' => _firstArgument(call.arguments, const <String>[
        'command',
        'test_cmd',
        'program',
      ]),
    'webfetch' => _stringArgument(call.arguments, 'url'),
    'websearch' => _stringArgument(call.arguments, 'query'),
    _ => null,
  };
  if (value == null || value.isEmpty) return const <String>['*'];
  return <String>[value];
}

/// 按候选键顺序取第一个非空字符串参数。
String? _firstArgument(Map<String, Object?> args, List<String> keys) {
  for (final String key in keys) {
    final String? value = _stringArgument(args, key);
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

/// 取字符串参数并去空白；非字符串或空串返回 `null`。
String? _stringArgument(Map<String, Object?> args, String key) {
  final Object? raw = args[key];
  if (raw is! String) return null;
  final String trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}
