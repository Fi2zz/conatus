/// prompt-evolver 的默认实现：失败分析 → 变体生成 → A/B 评估 → 晋升/回滚。
/// 晋升前后各版本经 [PromptStore] 存档；A/B 评估期间临时替换 prompt section，
/// 结束（含异常）后恢复。低质量轨迹由调用方筛选传入（见 [PromptEvolver.propose]）。
library;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'approval.dart';
import 'context_metrics.dart';
import 'eval.dart';
import 'prompt_evolver.dart';
import 'prompt_evolver_prompts.dart';
import 'prompt_store.dart';
import 'prompt_variant.dart';
import 'telemetry.dart';

/// 默认提示词进化器。
class DefaultPromptEvolver implements PromptEvolver {
  DefaultPromptEvolver({
    required LlmProvider llm,
    required Evaluator evaluator,
    required SystemPrompt prompt,
    List<EvalCase> evalCases = const <EvalCase>[],
    Approval? approval,
    Telemetry? telemetry,
    PromptStore? store,
    int minTraces = 10,
    int maxBudgetPerRun = 50000,
  })  : _llm = llm,
        _evaluator = evaluator,
        _prompt = prompt,
        _evalCases = evalCases,
        _approval = approval,
        _telemetry = telemetry,
        _store = store ?? PromptStore(),
        _minTraces = minTraces,
        _maxBudgetPerRun = maxBudgetPerRun;

  final LlmProvider _llm;
  final Evaluator _evaluator;
  final SystemPrompt _prompt;
  final List<EvalCase> _evalCases;
  final Approval? _approval;
  final Telemetry? _telemetry;
  final PromptStore _store;
  final int _minTraces;
  final int _maxBudgetPerRun;

  final Map<String, PromptSection> _originals = <String, PromptSection>{};
  PromptVariant? _current;

  @override
  List<PromptVariant> get history => _store.all;
  @override
  PromptVariant? get current => _current;

  /// 从存档恢复历史版本，并把最后一条作为当前版本。
  Future<void> restore() async {
    await _store.load();
    if (_store.all.isNotEmpty) _current = _store.all.last;
  }

  @override
  Future<PromptVariant?> propose({
    required String sectionName,
    required List<SessionEvent> lowQualityTraces,
  }) async {
    if (lowQualityTraces.length < _minTraces) return null;
    final String patterns =
        await analyzeFailurePatterns(_llm, lowQualityTraces);
    final PromptVariant variant = await generateVariant(
        llm: _llm,
        prompt: _prompt,
        sectionName: sectionName,
        failurePatterns: patterns,
        parentId: _current?.id);
    _telemetry?.emit(TelemetryEvent('prompt.proposed', data: <String, Object?>{
      'section': sectionName,
      'variant': variant.id
    }));
    return variant;
  }

  @override
  Future<EvolutionResult> evaluate(PromptVariant variant) async {
    final List<EvalCase> cases = _budgetedCases();
    final EvalReport baseline = await _evaluator.runAll(cases);
    _swapSection(variant.sectionName, variant.text);
    final EvalReport variantReport;
    try {
      variantReport = await _evaluator.runAll(cases);
    } finally {
      _restoreSection(variant.sectionName);
    }
    final double improvement = variantReport.passRate - baseline.passRate;
    return EvolutionResult(
        decision: _decide(improvement),
        variant: variant.copyWith(score: variantReport.passRate),
        baselineScore: baseline.passRate,
        variantScore: variantReport.passRate,
        improvement: improvement);
  }

  @override
  Future<bool> promote(PromptVariant variant, {double threshold = 0.05}) async {
    final EvolutionResult result = await evaluate(variant);
    final PromptVariant evaluated = result.variant;
    if (result.improvement < threshold) return false;

    final Approval? gate = _approval;
    if (gate != null) {
      final bool approved = await gate.request(ApprovalRequest(
        id: 'promote-${DateTime.now().microsecondsSinceEpoch}',
        toolName: 'promote_prompt',
        arguments: <String, Object?>{
          'section': evaluated.sectionName,
          'improvement': result.improvement,
          'variant': evaluated.id,
        },
        description:
            '提示词改进 +${(result.improvement * 100).toStringAsFixed(1)}%，确认晋升？\n${_preview(evaluated.text)}',
      ));
      if (!approved) return false;
    }

    await _archiveCurrent(evaluated.sectionName);
    _swapSection(evaluated.sectionName, evaluated.text);
    await _store.save(evaluated);
    _current = evaluated;
    _telemetry?.emit(TelemetryEvent('prompt.promoted', data: <String, Object?>{
      'variant': evaluated.id,
      'improvement': result.improvement
    }));
    return true;
  }

  @override
  Future<void> rollback(String variantId) async {
    final PromptVariant? target = _store.find(variantId);
    if (target == null) throw StateError('变体 "$variantId" 不存在');
    await _archiveCurrent(target.sectionName);
    _swapSection(target.sectionName, target.text);
    await _store.save(target);
    _current = target;
    _telemetry?.emit(TelemetryEvent('prompt.rolled_back',
        data: <String, Object?>{'variant': target.id}));
  }

  Future<void> _archiveCurrent(String sectionName) async {
    if (_current != null) return _store.save(_current!);
    await _store.save(PromptVariant(
        id: 'initial-${DateTime.now().microsecondsSinceEpoch}',
        sectionName: sectionName,
        text: sectionText(_prompt, sectionName),
        reason: '初始版本',
        createdAt: DateTime.now()));
  }

  void _swapSection(String name, String text) {
    final PromptSection? existing = _findSection(name);
    if (existing == null) throw StateError('prompt 段 "$name" 未注册');
    _originals[name] = existing;
    _prompt.remove(existing);
    _prompt.section(
        PromptSection(name: name, order: existing.order, text: () => text));
  }

  void _restoreSection(String name) {
    final PromptSection? original = _originals.remove(name);
    if (original == null) return;
    final PromptSection? currentSection = _findSection(name);
    if (currentSection != null) _prompt.remove(currentSection);
    _prompt.section(original);
  }

  PromptSection? _findSection(String name) {
    for (final PromptSection section in _prompt.sections) {
      if (section.name == name) return section;
    }
    return null;
  }

  EvolutionDecision _decide(double improvement) {
    if (improvement > 0.05) return EvolutionDecision.promote;
    if (improvement < -0.02) return EvolutionDecision.reject;
    return EvolutionDecision.insufficient;
  }

  List<EvalCase> _budgetedCases() {
    int spent = 0;
    return <EvalCase>[
      for (final EvalCase evalCase in _evalCases)
        if ((spent += estimateTokens(evalCase.input)) <= _maxBudgetPerRun)
          evalCase,
    ];
  }

  static String _preview(String text) =>
      text.length > 200 ? '${text.substring(0, 200)}…' : text;
}
