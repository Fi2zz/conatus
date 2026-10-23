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
      return ToolResult.success('没有可用的 MCP 资源', value: const <Object?>[]);
    }
    return ToolResult.success(text.toString(), value: rows);
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
      return ToolResult.failure(
        '未知 MCP server "$server"',
        error: ToolError('MCP_SERVER_UNKNOWN', 'unknown server "$server"'),
      );
    }
    final List<McpResourceContents> contents =
        await registry.readResource(server: server, uri: uri);
    if (contents.isEmpty) {
      return ToolResult.failure(
        '读取 MCP 资源失败或内容为空：$server $uri',
        error: const ToolError('MCP_RESOURCE_EMPTY', 'resource unavailable'),
      );
    }
    return ToolResult.success(
      <String>[for (final McpResourceContents item in contents) _render(item)]
          .join('\n\n'),
      value: <String, Object?>{
        'server': server,
        'uri': uri,
        'count': contents.length
      },
    );
  }
}

/// 把资源工具注册到 `ctx.tools`，返回已注册的工具。
///
/// [registry] 缺省取上下文的 `'mcp'` 服务（见 `provideMcp`）。
List<Tool> provideMcpResourceTools(
  Context ctx, {
  McpRegistry? registry,
}) {
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

ToolResult _unknownServer(String server) => ToolResult.failure(
      '未知 MCP server "$server"',
      error: ToolError('MCP_SERVER_UNKNOWN', 'unknown server "$server"'),
    );

String _render(McpResourceContents content) {
  final String? text = content.text;
  if (text != null) return _capText(text);
  final String? blob = content.blob;
  if (blob == null) return '（空内容）';
  return '[binary ${_blobLength(blob)} bytes]';
}

/// 二进制正文按解码后的字节数报大小（不需要把内容载入上下文）。
int _blobLength(String blob) {
  try {
    return base64.decode(blob).length;
  } on FormatException {
    return blob.length;
  }
}

/// 按 UTF-8 字节上限截断，避免切断多字节字符产生非法文本。
String _capText(String text) {
  final List<int> bytes = utf8.encode(text);
  if (bytes.length <= kMcpResourceContentLimit) return text;
  final String head = utf8.decode(
    bytes.sublist(0, kMcpResourceContentLimit),
    allowMalformed: true,
  );
  return '$head…（已截断）';
}

String? _blankToNull(String? value) {
  final String? trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
