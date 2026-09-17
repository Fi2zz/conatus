/// computer use Provider 接口：初始化桌面会话（无 Session 所有权）。
library;

import 'desktop.dart';

/// 计算机操作 Provider。
abstract class ComputerUseProvider {
  /// Provider 名字。
  String get name;

  /// 初始化 Provider。
  ///
  /// 返回的 [DesktopSession] **不绑定**任何 Session。
  /// 调用方负责协调跨 Session 的观察、操作和验证流程。
  ///
  /// 启动失败时释放此次尝试的注册。
  Future<DesktopSession> initialize();

  /// Provider 关闭时调用。
  ///
  /// 先停止接收工具调用，等待自有工作与资源清理完成，
  /// 再释放共享 Provider 注册。
  Future<void> dispose();
}
