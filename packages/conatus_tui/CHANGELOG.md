# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [0.15.0] — 2026-09-15

- 新增 `conatus_tui`：基于 [nocterm](https://pub.dev/packages/nocterm) 的文本 TUI。
  用 conatus Agent Loop 驱动多轮对话，会话事件投射为屏上消息，含斜杠命令菜单、
  会话选择面板、顶栏 / 状态栏与工具调用回显；支持 JSONL 会话持久化与恢复。
