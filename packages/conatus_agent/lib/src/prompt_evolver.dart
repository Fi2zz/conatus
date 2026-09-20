/// prompt-evolver 插件：根据 evaluation 反馈自动改进 system prompt。
///
/// 核心流程：分析低质量轨迹的失败模式 → LLM 生成变体 → 用 [Evaluator]
/// A/B 对比变体与当前 prompt → 通过阈值后经 [Approval] 人类确认才晋升；
/// 每个版本经 [PromptStore] 存档，可随时回滚。
///
/// 服务键 `'promptEvolver'`。依赖（缺省从上下文取，缺失时降级）：
/// `llm`（必需）、`evaluator` / `sessionLog` / `systemPrompt`（显式传入）、
/// `approval`（免审批）、`telemetry`（无埋点）、`database`（内存存档）。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'approval.dart';
import 'eval.dart';
import 'prompt_evolver_default.dart';
import 'prompt_store.dart';
import 'prompt_variant.dart';
import 'telemetry.dart';

/// 演化决策。
enum EvolutionDecision {
  /// 晋升：替换当前 prompt。
  promote,

  /// 拒绝：丢弃变体。
  reject,

  /// 需要更多数据：样本不足。
  insufficient,
}

/// 演化结果。
class EvolutionResult {
  const EvolutionResult({
    required this.decision,
    required this.variant,
    required this.baselineScore,
    required this.variantScore,
    required this.improvement,
  });

  /// 演化决策。
  final EvolutionDecision decision;

  /// 参与评估的变体（携带评估得分）。
  final PromptVariant variant;

  /// 当前 prompt 的通过率。
  final double baselineScore;

  /// 变体 prompt 的通过率。
  final double variantScore;

  /// 通过率差（变体减基线）。
  final double improvement;
}

/// 提示词进化器。
abstract class PromptEvolver {
  /// 分析低质量轨迹，生成 prompt 候选。
  ///
  /// 轨迹数不足 [minTraces] 时返回 `null`。
  Future<PromptVariant?> propose({
    required String sectionName,
    required List<SessionEvent> lowQualityTraces,
  });

  /// 用 evaluation 对比变体与当前 prompt。
  Future<EvolutionResult> evaluate(PromptVariant variant);

  /// 晋升：替换当前 prompt。需要人类确认。
  Future<bool> promote(PromptVariant variant, {double threshold = 0.05});

  /// 回滚到指定版本。
  Future<void> rollback(String variantId);

  /// 当前版本（最近晋升或回滚的变体）。
  PromptVariant? get current;

  /// 历史版本（按创建时间升序）。
  List<PromptVariant> get history;
}

/// `ctx.promptEvolver`：当前上下文可见的提示词进化器。
extension PromptEvolverContext on Context {
  /// 取当前上下文可见的 [PromptEvolver]（未提供时抛 [StateError]）。
  PromptEvolver get promptEvolver => require<PromptEvolver>('promptEvolver');
}

/// 提供 `'promptEvolver'` 服务。
///
/// [evaluator] / [sessionLog] / [prompt] 必需；[evalCases] 是 A/B 测试的固定
/// 用例集（缺省为空，此时 [PromptEvolver.evaluate] 得 `insufficient`）。
/// [sessionLog] 为契约依赖，当前轨迹由调用方筛选传入，留作后续自动收集。
/// `llm` 缺省取上下文 `'llm'`，缺失时抛 [StateError]。
PromptEvolver providePromptEvolver(
  Context ctx, {
  PromptEvolver? evolver,
  required Evaluator evaluator,
  required SessionLog sessionLog,
  required SystemPrompt prompt,
  List<EvalCase> evalCases = const <EvalCase>[],
  LlmProvider? llm,
  Approval? approval,
  Telemetry? telemetry,
  Database? database,
  int minTraces = 10,
  int maxBudgetPerRun = 50000,
}) {
  final LlmProvider? model = llm ?? ctx.get<LlmProvider>('llm');
  if (model == null) {
    throw StateError('promptEvolver 依赖 llm 服务，上下文中未提供');
  }
  final PromptEvolver resolved = evolver ??
      DefaultPromptEvolver(
        llm: model,
        evaluator: evaluator,
        prompt: prompt,
        evalCases: evalCases,
        approval: approval ?? ctx.get<Approval>('approval'),
        telemetry: telemetry ?? ctx.get<Telemetry>('telemetry'),
        store: PromptStore(database: database ?? ctx.get<Database>('database')),
        minTraces: minTraces,
        maxBudgetPerRun: maxBudgetPerRun,
      );
  ctx.provide('promptEvolver', resolved);
  return resolved;
}
