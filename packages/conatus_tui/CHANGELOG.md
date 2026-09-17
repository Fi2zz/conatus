# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

- 依赖新增 `conatus_compaction`：压缩服务（`provideCompaction`）由该包提供，
  装配时改从新包导入。
- 多智能体协作 UI（HANDOFF-12）：
  - 依赖新增 `conatus_team`、`conatus_tts`
  - 新增 `TeamSnapshot` / `ViewMode` 与 `TeamSubscription`（订阅
    `AgentTeam.changes`，事件驱动重建快照，可选成本 seam `TeamCostSource`）
  - 新增团队渲染件：`TeamStatusBar`（团队概况）、`MemberCard`、`TaskRow`、
    `TeamView`（成员列表 + 任务板）
  - 会话装配团队服务（`provideAgentTeam` + `provideTeamTools`），模型可用团队
    协作工具；`Ctrl+T` 切换对话 / 团队视图（输入框内优先于文本域转置快捷键）
  - 新增 `VoiceReporter`（订阅团队事件经 TTS 播报，`minInterval` 节流 + 可选
    音频目标）与 `summarizeTeamProgress` 进度摘要
  - 新增斜杠命令 `/team`（status / interrupt）与 `/task`（claim / release）

## [0.15.0] — 2026-09-15

- 新增 `conatus_tui`：基于 [nocterm](https://pub.dev/packages/nocterm) 的文本 TUI。
  用 conatus Agent Loop 驱动多轮对话，会话事件投射为屏上消息，含斜杠命令菜单、
  会话选择面板、顶栏 / 状态栏与工具调用回显；支持 JSONL 会话持久化与恢复。
- 新增 DeepSeek Demo（`example/deepseek_demo.dart`）：用 `DeepSeekProvider` 驱动
  TUI，未设置 `DEEPSEEK_API_KEY` 时退回离线脚本模型，无 Key 也能预览。
- `ConatusTuiRuntime.create` 支持注入 `llm` 与覆盖 `modelLabel`。
