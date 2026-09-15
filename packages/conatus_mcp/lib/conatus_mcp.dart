/// conatus 的 MCP（Model Context Protocol）客户端。
///
/// 提供三件事：
///
/// * **线协议词汇** — [McpMessage] / [McpError] / [McpServerInfo] / [McpTool] /
///   [McpToolResult] / [McpContent]，纯数据搬运，可单独用于协议调试；
/// * **传输与会话** — [McpTransport] 的三个实现（[StdioTransport]、
///   [HttpTransport]、[SseTransport]）与 [McpClient]（握手、
///   `tools/list` 分页发现、`tools/call`、超时与断连收敛）；
/// * **工具接入** — [McpToolAdapter] / [mcpToolRisk] 把服务端工具接进
///   `ToolRegistry`，[provideMcp] / [McpRegistry] 负责多 server 装配与生命周期。
///
/// ```dart
/// provideTools(app);
/// await provideMcp(app, <McpServerConfig>[
///   McpServerConfig(name: 'fs', type: McpTransportType.stdio, command: 'npx'),
/// ]);
/// ```
library;

export 'src/mcp.dart'
    show McpContext, provideMcp, resolveCredentialPlaceholders;
export 'src/mcp_client.dart' show McpClient;
export 'src/mcp_protocol.dart'
    show kMcpProtocolVersion, McpError, McpMessage, McpServerInfo;
export 'src/mcp_protocol_content.dart'
    show describeMcpContent, McpContent, McpToolResult;
export 'src/mcp_protocol_tool.dart' show McpTool;
export 'src/mcp_registry.dart' show McpRegistry;
export 'src/mcp_sse.dart' show parseSseEvents, SseEvent;
export 'src/mcp_tool.dart'
    show
        McpToolAdapter,
        McpToolAlias,
        mcpToolName,
        mcpToolRisk,
        toolResultFromMcp;
export 'src/mcp_transport.dart' show McpTransport;
export 'src/mcp_transport_http.dart' show HttpTransport;
export 'src/mcp_transport_sse.dart' show SseTransport;
export 'src/mcp_transport_stdio.dart' show StdioTransport;
export 'src/mcp_types.dart'
    show McpException, McpServerConfig, McpTransportType;
