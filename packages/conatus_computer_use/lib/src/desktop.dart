/// 桌面会话：**不绑定**任何 Session，调用方协调完整观察流程。
library;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_mcp/conatus_mcp.dart';

import 'screenshot.dart';

/// 桌面会话。**不绑定**任何 Session。
///
/// 调用方负责协调跨 Session 和独立 conatus 进程的完整观察、
/// 操作和验证流程。
abstract class DesktopSession {
  /// Provider 提供的工具声明（含参数 schema，注册时透传给模型）。
  List<McpTool> get tools;

  /// 调用 Provider 工具。
  ///
  /// 工具的 schema、结果渲染、图像支持由 Provider 拥有。
  /// 取消调用**无法撤销**桌面已收到的输入。
  Future<ToolResult> call(String toolName, Map<String, Object?> args);

  /// 捕获屏幕截图。
  ///
  /// 支持图像的模型路由在挂载附件存储时接收持久化截图；
  /// 不支持图像的路由接收现有 MCP 图像诊断。
  Future<Screenshot> capture({ScreenRegion? region});

  /// 等待自有工作与资源清理完成。
  Future<void> close();
}
