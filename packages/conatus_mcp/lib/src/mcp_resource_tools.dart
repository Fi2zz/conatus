/// MCP 资源工具：把 server 暴露的 resources 接到模型侧工具表。
///
/// 两个工具都是只读（[ToolRisk.low]）：`list_mcp_resources` 列清单，
/// `read_mcp_resource` 读单个 URI。文本直出，二进制只报解码后大小；单条
/// 内容超过 [kMcpResourceContentLimit] 时截断，避免一次读取刷爆上下文。
library;

import 'dart:convert';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'mcp_registry.dart';
import 'mcp_resource_types.dart';

part 'mcp_resource_render.dart';

/// 单条资源内容的最大输出字节数（64 KiB）。
const int kMcpResourceContentLimit = 64 * 1024;

/// 列举资源。
class ListMcpResourcesTool extends Tool {
  /// 构造。
  ListMcpResourcesTool({required this.registry});

  /// 要列举的注册表。
  final McpRegistry registry;

  @override
  String get name => 'list_mcp_resources';

  @override
  String get description => '列出已装配 MCP server 暴露的资源（可限定 server）。';

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('server', description: '限定某个 server；缺省列全部'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String? requested = _blankToNull(ctx.string('server'));
    if (requested != null && !registry.servers.contains(requested)) {
      return _unknownServer(requested);
    }
    final List<String> servers =
        requested == null ? registry.servers : <String>[requested];
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    final StringBuffer text = StringBuffer('MCP 资源：');
    for (final String server in servers) {
      final List<McpResource> resources =
          await registry.listResources(server: server);
      for (final McpResource resource in resources) {
        rows.add(<String, Object?>{
          'server': server,
          'uri': resource.uri,
          'name': resource.name,
          'description': resource.description,
          'mimeType': resource.mimeType,
        });
        text.write('\n- $server: ${resource.uri}');
        if (resource.name.isNotEmpty) text.write('（${resource.name}）');
        if (resource.mimeType != null) text.write(' [${resource.mimeType}]');
      }
    }
    if (rows.isEmpty) {
      return ToolResult.success(
        '没有可用的 MCP 资源${_errorDetail()}',
        value: const <Object?>[],
      );
    }
    return ToolResult.success(text.toString(), value: rows);
  }

  /// 列空时附上各 server 的最近失败原因（没有失败则为空串）。
  String _errorDetail() {
    final Map<String, String> errors = registry.lastErrors;
    if (errors.isEmpty) return '';
    return '\n${errors.entries.map((MapEntry<String, String> e) => '- ${e.key}: ${e.value}').join('\n')}';
  }
}

/// 读取一个资源。
class ReadMcpResourceTool extends Tool {
  /// 构造。
  ReadMcpResourceTool({required this.registry});

  /// 要读取的注册表。
  final McpRegistry registry;

  @override
  String get name => 'read_mcp_resource';

  @override
  String get description => '读取 MCP server 上的一个资源 URI；二进制返回大小占位。';

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('server', required: true, description: 'server 名'),
        ParamSpec.string('uri', required: true, description: '资源 URI'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String server = ctx.str('server').trim();
    final String uri = ctx.str('uri').trim();
    if (!registry.servers.contains(server)) {
      return _unknownServer(server);
    }
    final List<McpResourceContents> contents =
        await registry.readResource(server: server, uri: uri);
    if (contents.isEmpty) {
      final String? error = registry.lastErrorFor(server);
      return ToolResult.failure(
        error == null
            ? '读取 MCP 资源失败或内容为空：$server $uri'
            : '读取 MCP 资源失败：$server $uri（$error）',
        error: ToolError('MCP_RESOURCE_EMPTY', error ?? 'resource unavailable'),
      );
    }
    return ToolResult.success(
      <String>[for (final McpResourceContents item in contents) _render(item)]
          .join('\n\n'),
      value: <String, Object?>{
        'server': server,
        'uri': uri,
        'count': contents.length,
      },
    );
  }
}

/// 把资源工具注册到 `ctx.tools`，返回已注册的工具。
///
/// [registry] 缺省取上下文的 `'mcp'` 服务（见 `provideMcp`）。
List<Tool> provideMcpResourceTools(Context ctx, {McpRegistry? registry}) {
  final McpRegistry resolved = registry ?? ctx.require<McpRegistry>('mcp');
  final List<Tool> registered = <Tool>[
    ListMcpResourcesTool(registry: resolved),
    ReadMcpResourceTool(registry: resolved),
  ];
  for (final Tool tool in registered) {
    ctx.effect(() => ctx.tools.register(tool));
  }
  return registered;
}
