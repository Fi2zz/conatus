/// TUI 屏上消息模型：用户 / 助手气泡 + 工具 / 阶段 / 系统 / 导航提示。
library;

/// 一条屏上消息的角色。
enum TuiRole {
  /// 用户输入。
  user,

  /// 助手回复。
  assistant,

  /// 工具调用回显（成功 / 失败）。
  tool,

  /// 阶段提示（思考、计划等暗色行）。
  stage,

  /// 命令回执 / 提示信息。
  system,

  /// 会话迁移等导航事件。
  nav,
}

/// 屏上一条消息。
class TuiMessage {
  TuiMessage(this.role, this.text);

  /// 角色。
  final TuiRole role;

  /// 正文；可增量更新。
  String text;
}
