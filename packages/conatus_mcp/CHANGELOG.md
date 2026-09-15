# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [0.15.0] — 2026-09-15

- 新增 `conatus_mcp` 包：MCP（Model Context Protocol）客户端。
- JSON-RPC 2.0 / MCP 词汇：`McpMessage`、`McpError`、`McpServerInfo`、
  `McpTool`、`McpToolResult`、`McpContent`。
- 三种传输：`StdioTransport`（子进程）、`HttpTransport`（流式 POST）、
  `SseTransport`（长连接 + endpoint 事件），共享纯函数式 SSE 解析。
- `McpClient`：握手、`tools/list` 分页发现、`tools/call`、超时与断连收敛。
- `McpToolAdapter` / `McpToolAlias` / `mcpToolRisk`：把 MCP 工具接入
  `ToolRegistry`，服务端 `inputSchema` 直通、风险等级映射。
- `provideMcp` / `McpRegistry`：按 `McpServerConfig` 装配多台 server，
  支持 `${KEY}` 凭据占位符解析与短别名。
