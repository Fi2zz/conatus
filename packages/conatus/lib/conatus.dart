/// 时空可组合性（Spatiotemporal Composability）编程范式的 Dart 实现。
///
/// 本包是 monorepo 的**伞包（umbrella）**：自身不含实现，统一再导出各模块包，
/// 使 `import 'package:conatus/conatus.dart';` 保持向后兼容。
///
/// * [conatus_core]       — 核心范式：Context / EffectScope / Reactor
/// * [conatus_foundation] — 基础设施插件：timer / logger / loader / tools /
///                          shell / fs / session / system-prompt / memory / database
/// * [conatus_llm]        — 大模型接入（豆包 / DeepSeek）
/// * [conatus_search]     — 搜索能力缝 + web 工具
/// * [conatus_asr]        — ASR 能力缝（豆包/火山流式识别）+ transcribe_audio
/// * [conatus_agent]      — Agent Loop 与产品化：plan / sub-agent / reflection /
///                          telemetry / evaluation / approval / skill / recovery
library;

export 'package:conatus_agent/conatus_agent.dart';
export 'package:conatus_asr/conatus_asr.dart';
export 'package:conatus_core/conatus_core.dart';
export 'package:conatus_foundation/conatus_foundation.dart';
export 'package:conatus_llm/conatus_llm.dart';
export 'package:conatus_search/conatus_search.dart';
