/// Benchmark 适配器：接入 benchmark 的 rollout 与评估协议。
///
/// 参照 EvoOntology 论文在 BIRD / DDR-10K / InsightBench 上的验证方式。
/// ⚠️ 实验性：数据加载与 rollout 需接入外部 benchmark，此处只定义契约。
library;

import 'package:conatus_agent/conatus_agent.dart';

import '../builder/source.dart';
import '../evolver/evaluator.dart';
import '../ontology/layer.dart';

/// 一次 rollout 的结果。
class RolloutResult {
  const RolloutResult({
    required this.turn,
    required this.expected,
  });

  /// 实际执行轮。
  final AgentTurn turn;

  /// 期望结果（真值）。
  final String expected;
}

/// Benchmark 适配器。
abstract class EvolutionAdapter {
  /// Benchmark 名字。
  String get name;

  /// 加载数据源。
  Future<List<DataSource>> loadSources();

  /// 加载评估用例。
  Future<List<EvalCase>> loadCases();

  /// 运行一次 rollout。
  Future<RolloutResult> rollout({
    required OntologyLayer ontology,
    required BackboneConfig backbone,
    required EvalCase testCase,
  });

  /// 评估 rollout 结果（0.0 ~ 1.0）。
  double evaluate(RolloutResult result, EvalCase testCase);
}
