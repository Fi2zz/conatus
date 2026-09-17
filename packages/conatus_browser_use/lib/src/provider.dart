/// browser use Provider 接口：初始化 / 释放绑定 Session 的浏览器。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import 'session_browser.dart';

/// 浏览器操作 Provider。
abstract class BrowserUseProvider {
  /// Provider 名字。
  String get name;

  /// 为指定 Session 初始化浏览器。
  ///
  /// 返回的 [SessionBrowser] 绑定该 Session，跨轮次复用。
  /// 同一 Provider 实例内，一个浏览器只能被一个 Session 拥有。
  Future<SessionBrowser> initializeFor(Session session);

  /// 释放指定 Session 的浏览器。
  ///
  /// 清理会断开连接并保持外部浏览器运行（附加模式）
  /// 或关闭启动的浏览器（启动模式）。
  Future<void> release(Session session);

  /// Provider 关闭时调用。
  ///
  /// 先停止接收工具调用，等待自有工作与资源清理完成，
  /// 再释放共享 Provider 注册。
  Future<void> dispose();
}
