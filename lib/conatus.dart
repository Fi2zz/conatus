/// 时空可组合性（Spatiotemporal Composability）编程范式的 Dart 实现。
///
/// 本包是 monorepo 的**伞包（umbrella）**：自身不含实现，单入口再导出全部
/// 29 个模块包（15 个稳定包 + 14 个实验性包），
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
/// * [conatus_rag]        — 原始 RAG 能力：会话切分、嵌入索引与租户/可见性
///                          过滤的稠密检索 + rag_search 工具
///
/// 实验性包（API 可能破坏性变更）：
///
/// * [conatus_alerting]     — 告警规则与通知能力缝
/// * [conatus_browser_use]  — 浏览器操作（Browser Use）
/// * [conatus_computer_use] — 桌面操作（Computer Use）
/// * [conatus_diff]         — 文本差异内核：统一 diff 生成 / 解析、行级 LCS、hunk 应用
/// * [conatus_doc]         — 文档补丁引擎（人机双写故事层数据内核）
/// * [conatus_fs_tools]    — 文件工具：read / write / edit / list / glob + provideFsTools
/// * [conatus_harness]      — 可版本化 harness 制品（实验性）
/// * [conatus_intent]       — 意图路由
/// * [conatus_memory]       — 记忆写入策略能力（保留判定 + 轮次记录）
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
export 'package:conatus_context/conatus_context.dart';
export 'package:conatus_core/conatus_core.dart';
export 'package:conatus_credentials/conatus_credentials.dart';
export 'package:conatus_cron/conatus_cron.dart';
export 'package:conatus_diff/conatus_diff.dart';
export 'package:conatus_doc/conatus_doc.dart';
export 'package:conatus_foundation/conatus_foundation.dart';
export 'package:conatus_fs_tools/conatus_fs_tools.dart';
export 'package:conatus_harness/conatus_harness.dart';
export 'package:conatus_intent/conatus_intent.dart';
export 'package:conatus_llm/conatus_llm.dart';
export 'package:conatus_mcp/conatus_mcp.dart';
export 'package:conatus_memory/conatus_memory.dart';
export 'package:conatus_observability/conatus_observability.dart';
// ontology 的 MemoryStore / Constraint 与 foundation / workflow 同名：
// 伞包出口以稳定包与先存在的实验性包为准，ontology 侧隐藏（直接依赖
// conatus_ontology 包不受影响）。
export 'package:conatus_ontology/conatus_ontology.dart'
    hide Constraint, MemoryStore;
// rag 的 cosineSimilarity / estimateTokens 与 intent / agent 同名：
// 伞包出口以稳定包与先存在的实验性包为准，rag 侧隐藏（直接依赖
// conatus_rag 包不受影响）。
export 'package:conatus_rag/conatus_rag.dart'
    hide cosineSimilarity, estimateTokens;
export 'package:conatus_schedule/conatus_schedule.dart';
export 'package:conatus_search/conatus_search.dart';
export 'package:conatus_skill/conatus_skill.dart';
export 'package:conatus_tasks/conatus_tasks.dart';
export 'package:conatus_team/conatus_team.dart';
export 'package:conatus_tts/conatus_tts.dart';
export 'package:conatus_workflow/conatus_workflow.dart';
