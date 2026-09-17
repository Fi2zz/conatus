/// 绑定 Session 的浏览器实例、启动模式与配置。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

/// 浏览器启动模式。
enum BrowserLaunchMode {
  /// 启动新浏览器。Session 释放时关闭。
  launch,

  /// 附加到已有浏览器。Session 释放时断开连接，不关闭浏览器。
  attach,
}

/// 浏览器配置。
class BrowserConfig {
  const BrowserConfig({
    this.mode = BrowserLaunchMode.launch,
    this.profile,
    this.headless = true,
    this.viewport,
    this.userAgent,
  });

  /// 启动模式。
  final BrowserLaunchMode mode;

  /// 浏览器 profile（启动模式下的用户数据目录）。
  final String? profile;

  /// 是否无头运行。
  final bool headless;

  /// 视口尺寸。
  final ({int width, int height})? viewport;

  /// User-Agent。
  final String? userAgent;

  /// 复制并覆盖部分字段；只能覆盖成非空值。
  BrowserConfig copyWith({
    BrowserLaunchMode? mode,
    String? profile,
    bool? headless,
    ({int width, int height})? viewport,
    String? userAgent,
  }) =>
      BrowserConfig(
        mode: mode ?? this.mode,
        profile: profile ?? this.profile,
        headless: headless ?? this.headless,
        viewport: viewport ?? this.viewport,
        userAgent: userAgent ?? this.userAgent,
      );
}

/// 绑定 Session 的浏览器实例。
abstract class SessionBrowser {
  /// 所属 Session ID。
  String get sessionId;

  /// 浏览器是否活跃。
  bool get isActive;

  /// Provider 提供的工具列表。
  List<String> get toolNames;

  /// 调用 Provider 工具。
  ///
  /// 工具的 schema、结果渲染、图像支持由 Provider 拥有。
  Future<ToolResult> call(String toolName, Map<String, Object?> args);

  /// 等待自有工作与资源清理完成。
  Future<void> close();
}
