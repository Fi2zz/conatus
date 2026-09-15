/// 把 MCP 工具接入 `ToolRegistry` 的适配与风险映射。
library;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'mcp_client.dart';
import 'mcp_protocol_content.dart';
import 'mcp_protocol_tool.dart';
import 'mcp_types.dart';

/// 服务端工具在本地注册表里的名字：`server__tool`（双下划线，避开本地工具）。
String mcpToolName(String serverName, String toolName) =>
    '${serverName}__$toolName';

/// 把一台 server 的工具适配成 conatus [Tool]。
///
/// 入参 schema 由服务端下发，[ParamSpec] 表达不了任意 JSON Schema，因此
/// [params] 留空（空声明不做校验，多余参数不会被拒）而 [toSchema] 直接透传
/// 服务端 `inputSchema`。
///
/// 风险等级见 [mcpToolRisk]：**未声明的工具一律 [ToolRisk.medium]**，也就是
/// 默认走审批门控——宁可多问一次，也不要让未知的写操作静默执行。
class McpToolAdapter extends Tool {
  /// 构造。[client] 提供 server 归属，[tool] 是服务端声明。
  McpToolAdapter({required this.client, required this.tool});

  /// 工具所属的客户端（调用与命名都走它）。
  final McpClient client;

  /// 服务端的工具声明。
  final McpTool tool;

  @override
  String get name => mcpToolName(client.serverName, tool.name);

  @override
  String get description => tool.description ?? tool.title ?? tool.name;

  @override
  ToolRisk get riskLevel => mcpToolRisk(tool);

  @override
  String? get group => 'mcp:${client.serverName}';

  @override
  Map<String, Object?> toSchema() => <String, Object?>{
        'name': name,
        'description': description,
        'parameters': tool.inputSchema.isEmpty
            ? const <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{},
              }
            : tool.inputSchema,
      };

  @override
  Future<ToolResult> call(ToolContext context) async {
    try {
      final McpToolResult result =
          await client.callTool(tool.name, context.arguments);
      return toolResultFromMcp(result);
    } on McpException catch (error) {
      return ToolResult.failure(
        error.message,
        error: ToolError('MCP_ERROR', error.message),
      );
    }
  }
}

/// 给已注册的 MCP 工具加一个短别名。
///
/// 全名 `server__tool` 对模型偏长；别名工具除名字外与 [inner] 完全一致，
/// [toSchema] 里的 `name` 也换成别名。写操作应继续用全名，让调用日志里
/// 保留 server 归属。
class McpToolAlias extends Tool {
  /// 构造。[inner] 是被代理的工具，[alias] 是短名。
  const McpToolAlias({required this.inner, required this.alias});

  /// 被代理的工具。
  final Tool inner;

  /// 短名（注册表键）。
  final String alias;

  @override
  String get name => alias;

  @override
  String get description => inner.description;

  @override
  ToolRisk get riskLevel => inner.riskLevel;

  @override
  String? get group => inner.group;

  @override
  List<ParamSpec> get params => inner.params;

  @override
  Map<String, Object?> toSchema() => <String, Object?>{
        ...inner.toSchema(),
        'name': alias,
      };

  @override
  Future<ToolResult> call(ToolContext context) => inner.call(context);
}

/// 把 MCP 风险信号映射成 [ToolRisk]。
///
/// 判定顺序：
///
/// 1. 非标准扩展字段 [McpTool.riskLevel]：`readonly` / `read` → [ToolRisk.low]，
///    `write` / `mutating` → [ToolRisk.medium]，`destructive` / `admin` →
///    [ToolRisk.high]（大小写不敏感）；
/// 2. MCP 标准注解 `annotations.destructiveHint == true` → [ToolRisk.high]；
/// 3. `annotations.readOnlyHint == true` → [ToolRisk.low]；
/// 4. 其余（含什么都没声明）→ [ToolRisk.medium]，即默认需要审批。
ToolRisk mcpToolRisk(McpTool tool) {
  final ToolRisk? declared = _riskFromTag(tool.riskLevel);
  if (declared != null) return declared;
  final Map<String, Object?> annotations = tool.annotations;
  if (annotations['destructiveHint'] == true) return ToolRisk.high;
  if (annotations['readOnlyHint'] == true) return ToolRisk.low;
  return ToolRisk.medium;
}

/// 把一次 MCP 工具结果转成 [ToolResult]。
///
/// 线协议的 `isError` 映射到本地 [McpToolResult.failed]：失败时文本作为
/// 内容与 [ToolError.message]；成功时内容文本 + 结构化结果。
ToolResult toolResultFromMcp(McpToolResult result) {
  final String text = describeMcpContent(result.content);
  if (result.failed) {
    return ToolResult.failure(text, error: ToolError('MCP_TOOL_ERROR', text));
  }
  return ToolResult.success(text, value: result.structuredContent);
}

const Map<String, ToolRisk> _riskByTag = <String, ToolRisk>{
  'readonly': ToolRisk.low,
  'read': ToolRisk.low,
  'write': ToolRisk.medium,
  'mutating': ToolRisk.medium,
  'destructive': ToolRisk.high,
  'admin': ToolRisk.high,
};

ToolRisk? _riskFromTag(String? tag) =>
    tag == null ? null : _riskByTag[tag.toLowerCase()];
