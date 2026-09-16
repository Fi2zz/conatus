/// 时空可组合性（Spatiotemporal Composability）编程范式的 Dart 实现。
///
/// 本包是 monorepo 的**伞包（umbrella）**：自身不含实现，统一再导出各模块包，
/// 使 `import 'package:conatus/conatus.dart';` 保持向后兼容。
///
/// * [conatus_core]       — 核心范式：Context / EffectScope / Reactor
/// * [conatus_credentials] — 凭据管理：env / 文件 / Vault / AWS Secrets Manager
/// * [conatus_cron]       — 定时任务：at / every / daily / cron 规则调度 +
///                          运行记录持久化 + cron_* 管理工具
/// * [conatus_foundation] — 基础设施插件：timer / logger / loader / tools /
///                          shell / fs / session / session-log / system-prompt /
///                          memory / database
/// * [conatus_llm]        — 大模型接入（豆包 / DeepSeek）
/// * [conatus_mcp]        — MCP 客户端（stdio / HTTP / SSE 传输 + 工具接入）
/// * [conatus_schedule]   — 会话本地持久提醒（schedule_create / list / delete）
/// * [conatus_compaction] — 压缩能力缝（滚动摘要 + compaction/* 日志事件）
/// * [conatus_search]     — 搜索能力缝 + web 工具
/// * [conatus_skill]      — 技能加载：发现 SKILL.md 指令集 + 目录注入 + skill 工具
/// * [conatus_asr]        — ASR 能力缝（豆包/火山流式识别）+ transcribe_audio
/// * [conatus_tts]        — TTS 能力缝（豆包/火山语音合成）+ 音频输出接口
/// * [conatus_agent]      — Agent Loop 与产品化：plan / sub-agent / reflection /
///                          telemetry / evaluation / approval / skill / recovery
library;

export 'package:conatus_agent/conatus_agent.dart';
export 'package:conatus_asr/conatus_asr.dart';
export 'package:conatus_compaction/conatus_compaction.dart';
export 'package:conatus_core/conatus_core.dart';
export 'package:conatus_credentials/conatus_credentials.dart';
export 'package:conatus_cron/conatus_cron.dart';
export 'package:conatus_foundation/conatus_foundation.dart';
export 'package:conatus_llm/conatus_llm.dart';
export 'package:conatus_mcp/conatus_mcp.dart';
export 'package:conatus_schedule/conatus_schedule.dart';
export 'package:conatus_search/conatus_search.dart';
export 'package:conatus_skill/conatus_skill.dart';
export 'package:conatus_tts/conatus_tts.dart';
