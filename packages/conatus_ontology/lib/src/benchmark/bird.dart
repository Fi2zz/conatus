/// BIRD benchmark 适配器（Text-to-SQL，Execution Accuracy 评估）。
///
/// ⚠️ 实验性骨架：数据加载与 rollout 需接入外部 BIRD 数据集，
/// 此处契约先行，具体数据路径由接入方填充。
library;

import 'package:conatus_agent/conatus_agent.dart';

import '../builder/source.dart';
import '../evolver/evaluator.dart';
import '../ontology/layer.dart';
import 'adapter.dart';

/// BIRD 适配器。
class BirdAdapter implements EvolutionAdapter {
  const BirdAdapter();

  @override
  String get name => 'bird';

  @override
  Future<List<DataSource>> loadSources() async {
    // TODO: 接入 BIRD 数据库 schema（schema.json → DataSource）。
    return const <DataSource>[];
  }

  @override
  Future<List<EvalCase>> loadCases() async {
    // TODO: 接入 BIRD 训练/开发集问题。
    return const <EvalCase>[];
  }

  @override
  Future<RolloutResult> rollout({
    required OntologyLayer ontology,
    required BackboneConfig backbone,
    required EvalCase testCase,
  }) {
    // TODO: 用 backbone 驱动的 Text-to-SQL Agent 执行查询。
    throw UnimplementedError('BIRD rollout 需要接入外部数据与 Agent');
  }

  /// Execution Accuracy：执行结果与真值数据库一致得 1 分，否则 0 分。
  @override
  double evaluate(RolloutResult result, EvalCase testCase) {
    return result.turn.reply.trim() == result.expected.trim() ? 1.0 : 0.0;
  }
}
