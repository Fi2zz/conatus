# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

- **安全（E-10）**：`mcpToolRisk` 未声明风险的缺省从 `medium` 提级为 `high`
  （标签无法识别同样按 `high`）。原因：审批阈值缺省是 `high`（`instrumentApproval`
  与宿主默认权限模式），`medium` 不进审批——与文档承诺的「未声明默认需要审批」
  矛盾；MCP stdio 子进程不经本地沙箱，审批是未知风险的唯一防线，按 fail-closed
  提级。服务端显式声明 `readOnlyHint` / `riskLevel` 后仍按声明分级。

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
