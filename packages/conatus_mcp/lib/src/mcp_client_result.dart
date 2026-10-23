/// 响应解包：把 JSON-RPC 响应收成 `result` 映射，失败则抛 [McpException]。
library;

import 'mcp_json.dart';
import 'mcp_protocol.dart';
import 'mcp_types.dart';

/// 取出响应的 `result` 对象：失败响应抛 `protocol-error`，形态不对抛
/// `malformed-result`。
Map<String, Object?> mcpResultOf(McpMessage response) {
  final McpError? error = response.error;
  if (error != null) {
    throw McpException('protocol-error', '${error.code}: ${error.message}');
  }
  final Map<String, Object?>? result = mcpMap(response.result);
  if (result == null) {
    throw const McpException('malformed-result', '响应缺少 result 对象');
  }
  return result;
}

/// 与 [mcpResultOf] 相同，但把「方法未实现」（JSON-RPC `-32601`）收成 `null`。
///
/// 协议层用它表达「这台 server 没有这项能力」：调用方返回空表，而不是把
/// 整个连接判死。
Map<String, Object?>? mcpOptionalResult(McpMessage response) {
  if (response.error?.code == -32601) return null;
  return mcpResultOf(response);
}
