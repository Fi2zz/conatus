/// Backbone-conditional 配对评估：针对特定 backbone 的条件门控。
library;

import 'package:conatus_agent/conatus_agent.dart';

import '../ontology/layer.dart';
import 'evaluator.dart';

/// 配对评估器。
///
/// 对每个 backbone：Parent 与 Candidate 用**同一数据、同一 Agent、
/// 同一解码设置、同一交互预算**对比（`apply` 回调切换生效层），
/// 任一 backbone 改进达到阈值即通过。
class PairedEvaluator {
  const PairedEvaluator({
    required this.resolver,
    required this.backbones,
    this.threshold = 0.05,
  });

  /// 按 backbone 解析评估器（测试可注入 Mock）。
  final Evaluator Function(BackboneConfig backbone) resolver;
  final List<BackboneConfig> backbones;
  final double threshold;

  /// 对每个 backbone 做配对评估。
  ///
  /// [cases] 为评估用例；[apply] 在每轮前切换生效层（由宿主实现）。
  Future<ConditionalEvalResult> evaluate({
    required OntologyLayer parent,
    required OntologyLayer candidate,
    required List<EvalCase> cases,
    required Future<void> Function(OntologyLayer layer) apply,
  }) async {
    for (final BackboneConfig backbone in backbones) {
      final Evaluator evaluator = resolver(backbone);
      await apply(parent);
      final EvalReport baseline = await evaluator.runAll(cases);
      await apply(candidate);
      final EvalReport candidateReport = await evaluator.runAll(cases);
      final double improvement = candidateReport.passRate - baseline.passRate;
      if (improvement >= threshold) {
        return ConditionalEvalResult(
          backbone: backbone,
          baselineScore: baseline.passRate,
          candidateScore: candidateReport.passRate,
          improvement: improvement,
          passed: true,
        );
      }
    }
    return ConditionalEvalResult(
      backbone: backbones.first,
      baselineScore: 0,
      candidateScore: 0,
      improvement: 0,
      passed: false,
    );
  }
}
