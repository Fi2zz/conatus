# conatus_mcp

conatus 的 [MCP](https://modelcontextprotocol.io)（Model Context Protocol）客户端：
把外部 MCP server 的工具接进 `ToolRegistry`，模型看到的就是一张统一的工具表。

## 组成

| 层 | 类型 | 作用 |
|----|------|------|
| 线协议 | `McpMessage` / `McpError` / `McpServerInfo` | JSON-RPC 2.0 信封与握手结果 |
| 工具词汇 | `McpTool` / `McpToolResult` / `McpContent` | 服务端工具声明与调用结果 |
| 传输 | `McpTransport` | 连接抽象（`connect` / `send` / `messages` / `diagnostics`） |
| 会话 | `McpClient` | 握手、`tools/list` 分页发现、`tools/call`、超时与断连 |
| 工具接入 | `McpToolAdapter` / `mcpToolRisk` | 服务端工具 → conatus `Tool` |
| 装配 | `provideMcp` / `McpRegistry` | 多 server 连接、别名、生命周期 |

## 传输类型

| 类型 | 用途 | 认证方式 |
|------|------|----------|
| `McpTransportType.stdio` | 本地子进程（`npx` 起的官方 server 等），stdin/stdout 逐行 JSON-RPC | 环境变量（`env`），由子进程自己读 |
| `McpTransportType.http` | 远端 Streamable HTTP：每条消息一次 `POST` | 请求头（`headers`，如 `Authorization: Bearer …`） |
| `McpTransportType.sse` | 远端 SSE：`GET` 建长连接，服务端先给 `event: endpoint` 的 POST 地址 | 同 HTTP |

## 接线

```dart
import 'package:conatus/conatus.dart';

final app = Context.root();
provideTools(app);

await provideMcp(app, <McpServerConfig>[
  // 本地：官方 filesystem server
  McpServerConfig(
    name: 'fs',
    type: McpTransportType.stdio,
    command: 'npx',
    args: <String>['-y', '@modelcontextprotocol/server-filesystem', '/tmp'],
  ),
  // 远端：凭据走 ${KEY} 占位符
  McpServerConfig(
    name: 'remote',
    type: McpTransportType.http,
    url: 'https://mcp.example.com/mcp',
    headers: <String, String>{'Authorization': 'Bearer ${REMOTE_TOKEN}'},
  ),
], credentials: credentials, aliases: <String, String>{
  'read_file': 'fs__read_file',
});
```

`env` 与 `headers` 的值支持 `${KEY}` 占位符，由 `credentials.get('KEY')` 解析；
解析不了（没有凭据服务、键不存在、取凭据抛错）时**占位符原样保留**，不抛错、
不打印。也可以手动调用 `resolveCredentialPlaceholders(raw, credentials)`。

> **注意**：解析后的映射可能含明文凭据，**不得**把它写进日志、事件、会话记录或
> 任何模型可见的字段。要排查就用键名（`REMOTE_TOKEN`），不要用值。

## 工具命名与风险映射

服务端工具注册为 `server__tool`（双下划线，避开本地同名工具）；`group` 是
`mcp:<server>`，Session Log 里据此归因到具体 server。入参 schema 由服务端下发，
`toSchema()` 直接透传 `inputSchema`（为空时回退 `{"type":"object","properties":{}}`）。

| 服务端信号 | 本地 `ToolRisk` |
|------------|-----------------|
| 非标准 `riskLevel: readonly` / `read` | `low` |
| `annotations.readOnlyHint == true` | `low` |
| 非标准 `riskLevel: write` / `mutating` | `medium` |
| 什么都没声明 | `medium` |
| 非标准 `riskLevel: destructive` / `admin` | `high` |
| `annotations.destructiveHint == true` | `high` |

判定顺序是「非标准 `riskLevel` → `destructiveHint` → `readOnlyHint` → 缺省
`medium`」。**默认 `medium` 意味着默认需要审批**：MCP server 是外部进程，宁可
多问一次，也不要让未知的写操作静默执行。

## 生命周期

- `ctx.dispose()` → `McpRegistry.close()` → 断开全部连接并注销工具（进程被 kill、
  SSE 长连接被取消、HTTP client 关闭）；
- 某个 server 断连（崩溃、网络掉线）→ 该 server 的工具**全部注销**，其余 server
  继续可用，`ctx.mcp.servers` 里不再有它；宿主可订阅
  `clientOf(name)?.disconnects` / `diagnostics` 接自己的日志与告警；
- 请求超时（默认 30s，`McpClient(timeout:)` 可调）只让这一次调用失败，不算断连。

## 环境变量

本包自身不读环境变量：`stdio` 子进程继承父进程环境并叠加 `McpServerConfig.env`；
`${KEY}` 占位符由宿主的 `Credentials` 实现解析（例如 `EnvCredentials` 直接读环境
变量）。

## 自定义传输

`provideMcp(..., transportFactory: (McpServerConfig config) => MyTransport())` 可替换
传输实现（测试也用这个缝）；`McpTransport` 只要求 `connect` / `disconnect` /
`send` / `messages` / `diagnostics` 五个成员。
