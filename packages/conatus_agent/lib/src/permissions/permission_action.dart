/// 工具名 → 权限动作 / 资源的映射。
///
/// 动作是规则匹配的左边（`PermissionRule.action`），必须**精确**且与设计文档
/// 的动作表一致：路径工具归一到 `read` / `edit`，命令类归一到 `shell`，联网
/// 工具是 `websearch` / `webfetch`，子代理是 `subagent`，MCP 工具
/// `server__tool` 归一为 `server_tool`；未列出的工具直接用工具名，新增工具
/// 无需改映射也能被规则命中。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import 'permission_path.dart';

/// 具名工具的动作归一表（与设计文档「动作映射」表一致）。
const Map<String, String> _toolActions = <String, String>{
  'read_file': 'read',
  'list_files': 'read',
  'rg': 'grep',
  'glob': 'glob',
  'write_file': 'edit',
  'edit_file': 'edit',
  'apply_patch': 'edit',
  'run_command': 'shell',
  'run_tests': 'shell',
  'run_code': 'shell',
  'run_command_background': 'shell',
  'list_background_tasks': 'shell',
  'background_output': 'shell',
  'background_kill': 'shell',
  'web_search': 'websearch',
  'fetch_url': 'webfetch',
  'spawn_agent': 'subagent',
  'skill': 'skill',
  'ask_user': 'question',
};

/// 以路径为资源的动作：资源需要规范化。
const Set<String> _pathActions = <String>{'read', 'edit', 'glob'};

/// MCP 工具名里的 server / tool 分隔符。
const String _mcpSeparator = '__';

/// 取 [toolName] 的权限动作。
String permissionActionFor(String toolName) {
  if (toolName.contains(_mcpSeparator)) {
    return toolName.replaceAll(_mcpSeparator, '_');
  }
  return _toolActions[toolName] ?? toolName;
}

/// [action] 是否把路径当作资源（`read` / `edit` / `glob`）。
bool permissionActionUsesPath(String action) => _pathActions.contains(action);

/// 取一次调用的权限资源列表。
///
/// 路径动作返回规范化后的路径；shell 用命令串（`command` / `test_cmd` /
/// `program`）；联网工具用 URL / 查询词；子代理用 agent id（缺省 `default`）；
/// 其余（含 MCP、skill、question）用通配 `*`。空值同样落回 `*`。
List<String> permissionResourcesFor(
  ToolCall call,
  List<String> pathArgs,
) {
  final String action = permissionActionFor(call.name);
  if (permissionActionUsesPath(action) && pathArgs.isNotEmpty) {
    return <String>[
      for (final String path in pathArgs) normalizePermissionPath(path),
    ];
  }
  final String? value = switch (action) {
    'shell' => _firstArgument(call.arguments, const <String>[
        'command',
        'test_cmd',
        'program',
      ]),
    'webfetch' => _stringArgument(call.arguments, 'url'),
    'websearch' => _stringArgument(call.arguments, 'query'),
    'subagent' => _stringArgument(call.arguments, 'agent') ?? 'default',
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
