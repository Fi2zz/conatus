/// 时空可组合性（Spatiotemporal Composability）编程范式的 Dart 实现。
///
/// 本包是 monorepo 的**伞包（umbrella）**：自身不含实现，单入口再导出全部
/// 22 个模块包（14 个稳定包 + 8 个实验性包），
/// 使 `import 'package:conatus/conatus.dart';` 即完整公开 API。
/// 实验性包 API 可能破坏性变更，生产依赖前见各包 README。
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
/// * [conatus_tasks]      — 任务中心：Agent Loop / sub-agent / shell / schedule
///                          运行时任务追踪（任务树 + task/changed 持久化 +
///                          list_tasks / cancel_task 工具）
/// * [conatus_asr]        — ASR 能力缝（豆包/火山流式识别）+ transcribe_audio
/// * [conatus_tts]        — TTS 能力缝（豆包/火山语音合成）+ 音频输出接口
/// * [conatus_agent]      — Agent Loop 与产品化：plan / sub-agent / reflection /
///                          telemetry / evaluation / approval / skill / recovery
///
/// 实验性包（API 可能破坏性变更）：
///
/// * [conatus_alerting]     — 告警规则与通知能力缝
/// * [conatus_browser_use]  — 浏览器操作（Browser Use）
/// * [conatus_computer_use] — 桌面操作（Computer Use）
/// * [conatus_intent]       — 意图路由
/// * [conatus_observability]— 可观测性导出（trace/span 构建）
/// * [conatus_ontology]     — 自进化本体层（EvoOntology 适配）
/// * [conatus_team]         — 多智能体协作
/// * [conatus_workflow]     — 流程编排
library;

export 'package:conatus_agent/conatus_agent.dart';
export 'package:conatus_alerting/conatus_alerting.dart';
export 'package:conatus_asr/conatus_asr.dart';
export 'package:conatus_browser_use/conatus_browser_use.dart';
export 'package:conatus_compaction/conatus_compaction.dart';
export 'package:conatus_computer_use/conatus_computer_use.dart';
export 'package:conatus_core/conatus_core.dart';
export 'package:conatus_credentials/conatus_credentials.dart';
export 'package:conatus_cron/conatus_cron.dart';
export 'package:conatus_foundation/conatus_foundation.dart';
export 'package:conatus_intent/conatus_intent.dart';
export 'package:conatus_llm/conatus_llm.dart';
export 'package:conatus_mcp/conatus_mcp.dart';
export 'package:conatus_observability/conatus_observability.dart';
// ontology 的 MemoryStore / Constraint 与 foundation / workflow 同名：
// 伞包出口以稳定包与先存在的实验性包为准，ontology 侧隐藏（直接依赖
// conatus_ontology 包不受影响）。
export 'package:conatus_ontology/conatus_ontology.dart'
    hide Constraint, MemoryStore;
export 'package:conatus_schedule/conatus_schedule.dart';
export 'package:conatus_search/conatus_search.dart';
export 'package:conatus_skill/conatus_skill.dart';
export 'package:conatus_tasks/conatus_tasks.dart';
export 'package:conatus_team/conatus_team.dart';
export 'package:conatus_tts/conatus_tts.dart';
export 'package:conatus_workflow/conatus_workflow.dart';
