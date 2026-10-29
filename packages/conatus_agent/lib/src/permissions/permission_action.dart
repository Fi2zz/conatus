/// 工具名 → 权限动作 / 资源的映射。
///
/// 动作是规则匹配的左边（`PermissionRule.action`），必须**精确**且与设计文档
/// 的动作表一致：路径工具归一到 `read` / `edit`，命令类归一到 `bash`，联网
/// 工具是 `websearch` / `webfetch`，子代理是 `task`，MCP 工具
/// `server__tool` 归一为 `server_tool`；未列出的工具直接用工具名，新增工具
/// 无需改映射也能被规则命中。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import 'permission_patch.dart';
import 'permission_path.dart';

/// 具名工具的动作归一表（动作名与 OpenCode permission key 一致）。
///
/// 工具名与动作名同名的条目走兜底（[permissionActionFor] 直接返回工具名），
/// 这里只保留需要改名的条目。git 写工具归一到 `bash`：它们经 `runGit` 执行
/// 真实 git 命令，规则 `action="bash", resource="git *"` 必须能拦住，否则
/// 「只允许只读 git」的策略会被 `git_add` / `git_commit` / `git_branch` /
/// `git_stash` 绕过。
const Map<String, String> _toolActions = <String, String>{
  'list': 'read',
  'write': 'edit',
  'apply_patch': 'edit',
  'run_tests': 'bash',
  'run_code': 'bash',
  'run_command_background': 'bash',
  'list_background_tasks': 'bash',
  'background_output': 'bash',
  'background_kill': 'bash',
  'git_add': 'bash',
  'git_commit': 'bash',
  'git_branch': 'bash',
  'git_stash': 'bash',
};

/// 以路径为资源的动作：资源需要规范化。
///
/// `external_directory` 也在此列：它的规则资源是路径 pattern（`~/shared/*`
/// 这类写法需要展开与按 workdir 解析），否则规则永远匹配不上判定器给出的
/// 绝对边界。
const Set<String> _pathActions = <String>{
  'read',
  'edit',
  'glob',
  'external_directory',
};

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

/// 取一次调用涉及的**文件路径**（用于 `external_directory` 判定）。
///
/// `apply_patch` 从补丁头解析；`glob` 用搜索根 `path`；`read` / `edit` 用声明
/// 的路径参数。非路径动作返回空列表。
List<String> permissionPathsFor(ToolCall call, List<String> pathArgs) {
  final String action = permissionActionFor(call.name);
  if (!permissionActionUsesPath(action)) return const <String>[];
  if (call.name == 'apply_patch') {
    return permissionPatchPaths(_stringArgument(call.arguments, 'patch') ?? '');
  }
  return <String>[
    for (final String path in pathArgs) normalizePermissionPath(path),
  ];
}

/// 取一次调用的权限资源列表。
///
/// - `read` / `edit`：规范化路径；`apply_patch` 解析补丁内每个目标路径，
///   解析不出时落回 `*`；
/// - `glob`：请求的 pattern；
/// - `grep`：请求的 pattern（`rg` 的搜索表达式）；
/// - `bash`：命令 / git 写工具的实际 argv（`git add ...` 等）；
/// - `skill`：请求的技能 id（参数 `name`）；
/// - bash / web / task：命令 / URL / 查询词 / agent id（`task` 取
///   `task` 的 `agent` 参数，缺省 `default`；因此按
///   `task/default` 写的旧规则不再命中带 `agent` 的调用）；
/// - `list_mcp_resources`：`server`（缺省 `*`）；
/// - `read_mcp_resource`：`<server>:<uri>`（缺 uri 时只给 server）；
/// - 其余（含其他 MCP 工具、question）：`*`。空值同样落回 `*`。
List<String> permissionResourcesFor(
  ToolCall call,
  List<String> pathArgs,
) {
  final String action = permissionActionFor(call.name);
  final List<String>? mcp = _mcpResource(call);
  if (mcp != null) return mcp;
  if (action == 'glob' || action == 'grep') {
    return <String>[_stringArgument(call.arguments, 'pattern') ?? '*'];
  }
  if (action == 'read' || action == 'edit') {
    final List<String> paths = permissionPathsFor(call, pathArgs);
    if (paths.isNotEmpty) return paths;
  }
  final String? value = switch (action) {
    'bash' => _gitResource(call) ??
        _firstArgument(call.arguments, const <String>[
          'command',
          'test_cmd',
          'program',
        ]),
    'webfetch' => _stringArgument(call.arguments, 'url'),
    'websearch' => _stringArgument(call.arguments, 'query'),
    'skill' => _stringArgument(call.arguments, 'name'),
    'task' => _stringArgument(call.arguments, 'agent') ?? 'default',
    _ => null,
  };
  if (value == null || value.isEmpty) return const <String>['*'];
  return <String>[value];
}

/// MCP 资源工具的旧式动作别名：`<server>_list_mcp_resources` /
/// `<server>_read_mcp_resource`。
///
/// 设计 §6.2 用 server 前缀做动作；现行实现按调用参数把资源细化到 server，
/// 但存量规则（含文档示例）仍可能写成前缀形式。判定器会同时评估别名，
/// 取更严格的结果；没有 `server` 参数时不产生别名。
String? mcpResourceAliasAction(ToolCall call) {
  final String? server = _stringArgument(call.arguments, 'server')?.trim();
  if (server == null || server.isEmpty) return null;
  switch (call.name) {
    case 'list_mcp_resources':
      return '${server}_list_mcp_resources';
    case 'read_mcp_resource':
      return '${server}_read_mcp_resource';
  }
  return null;
}

/// MCP 资源工具的按调用参数资源。
///
/// 权限动作仍是工具名（`permissionActionFor` 只看得到名字）——这是对设计
/// §6.2「`<server>_list_mcp_resources`」的偏差：动作层拿不到参数，不能按
/// server 派生动作。资源细化到 server / `<server>:<uri>` 后，规则
/// `action="list_mcp_resources", resource="sentry"` 与
/// `action="read_mcp_resource", resource="sentry:*"` 仍可只放行 / 拒绝单台。
List<String>? _mcpResource(ToolCall call) {
  switch (call.name) {
    case 'list_mcp_resources':
      return <String>[_stringArgument(call.arguments, 'server') ?? '*'];
    case 'read_mcp_resource':
      final String server = _stringArgument(call.arguments, 'server') ?? '*';
      final String? uri = _stringArgument(call.arguments, 'uri');
      return <String>[uri == null ? server : '$server:$uri'];
  }
  return null;
}

/// 参与 `external_directory` 判定的路径。///
/// 与 [permissionPathsFor] 的区别：`grep`（`rg`）的搜索根 `path` 不在
/// `Tool.pathParams` 里，但 `rg(path: "/")` 同样是越界读取。这里把它并进来做
/// **边界判定**，不并进权限资源——否则每次 rg 都会多出一条「路径信任」询问。
List<String> permissionBoundaryPathsFor(
  ToolCall call,
  List<String> pathArgs,
) {
  final String action = permissionActionFor(call.name);
  if (action != 'grep') return permissionPathsFor(call, pathArgs);
  final String? searchPath = _stringArgument(call.arguments, 'path');
  final List<String> paths = <String>[
    if (searchPath != null) searchPath,
    ...pathArgs,
  ];
  return <String>[
    for (final String path in paths) normalizePermissionPath(path),
  ];
}

/// git 写工具的等价命令行，用于 `bash` 规则匹配。
///
/// 与 `git_write_tools.dart` 拼的 argv 保持同形（前缀 `git <子命令>`）；规则
/// 通常写成 `git *` / `git add *`，只依赖前缀。返回 `null` 表示不是 git 写
/// 工具（落回普通命令参数）。
String? _gitResource(ToolCall call) {
  final Map<String, Object?> args = call.arguments;
  switch (call.name) {
    case 'git_add':
      if (args['all'] == true) return 'git add -A';
      final List<String> paths = _stringList(args['paths']);
      return paths.isEmpty ? 'git add' : 'git add -- ${paths.join(' ')}';
    case 'git_commit':
      final String? message = _stringArgument(args, 'message');
      return message == null ? 'git commit' : 'git commit -m $message';
    case 'git_branch':
      if (args['list'] == true) return 'git branch --list';
      final String name = _stringArgument(args, 'name') ?? '';
      return args['create'] == true
          ? 'git checkout -b $name'.trimRight()
          : 'git checkout $name'.trimRight();
    case 'git_stash':
      if (args['restore'] == true) return 'git stash list';
      return args['keep'] == true ? 'git stash push' : 'git stash pop';
  }
  return null;
}

List<String> _stringList(Object? raw) => raw is List
    ? <String>[
        for (final Object? item in raw)
          if (item is String) item
      ]
    : const <String>[];

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
