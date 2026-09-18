/// `launch_app` 成功后的前台化编排。
///
/// CuaDriver 的 `launch_app` **刻意后台启动**(`the target does NOT come to the
/// foreground`);把应用带到前台需要再调 `bring_to_front`。本文件提供该编排的
/// 纯函数部分(Provider 会话层负责实际调用)。
library;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_mcp/conatus_mcp.dart';

/// 打开应用的 MCP 工具名。
const String launchAppToolName = 'launch_app';

/// 从 `launch_app` 结果中提取已启动应用的 pid。
///
/// CuaDriver 结构化返回 `{pid, bundle_id, name, windows}`;缺失或非 int 返回 null
/// (调用方应跳过前台化,不报错)。
int? launchedPid(McpToolResult raw) {
  final Object? pid = raw.structuredContent?['pid'];
  return pid is int ? pid : null;
}

/// 合并 `launch_app` 结果与自动 `bring_to_front` 结果。
///
/// content 保留 launch_app 文本并追加前台化摘要;value 保持 launch_app 的结构化
/// 结果(模型仍能拿到 pid / windows)。bring_to_front 失败**不**判整个操作失败
/// (launch_app 成功是主结果),仅在文本注明。
ToolResult mergeLaunchResult(ToolResult launched, ToolResult bringResult) {
  final String bring = bringResult.isError
      ? 'bring_to_front: failed: '
          '${bringResult.error?.message ?? bringResult.content}'
      : 'bring_to_front: ok';
  return ToolResult.success(
    '${launched.content}\n\n$bring',
    value: launched.value,
  );
}
