/// 通用进化器抽象：PromptEvolver 与 OntologyEvolver 的统一模式。
///
/// 仅在本包内定义，不改动 `conatus_agent` 的 `PromptEvolver` 公共 API。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import '../runtime/service.dart';
import 'evaluator.dart';
import 'evolver.dart';

/// 进化候选：payload 为进化对象本身。
class EvolverVariant<T> {
  const EvolverVariant({
    required this.id,
    required this.payload,
    this.reason,
  });

  final String id;
  final T payload;
  final String? reason;
}

/// 进化评估结果。
class EvolutionOutcome {
  const EvolutionOutcome({
    required this.baselineScore,
    required this.candidateScore,
    required this.improvement,
    required this.passed,
  });

  final double baselineScore;
  final double candidateScore;
  final double improvement;
  final bool passed;
}

/// 通用进化器。
abstract class Evolver<T> {
  /// 基于信号（失败轨迹等）提出候选。
  Future<EvolverVariant<T>> propose({
    required T current,
    required List<SessionEvent> signals,
  });

  /// 配对评估候选。
  Future<EvolutionOutcome> evaluate(EvolverVariant<T> candidate);

  /// 门控发布候选。
  Future<bool> publish(EvolverVariant<T> candidate, {double threshold = 0.05});
}

/// 把 [OntologyService] 适配为 `Evolver<OntologyVariant>`。
class OntologyEvolver implements Evolver<OntologyVariant> {
  const OntologyEvolver(this.service);

  final OntologyService service;

  @override
  Future<EvolverVariant<OntologyVariant>> propose({
    required OntologyVariant current,
    required List<SessionEvent> signals,
  }) async {
    final OntologyVariant variant = await service.evolve(trajectories: signals);
    return EvolverVariant<OntologyVariant>(
      id: variant.id,
      payload: variant,
      reason: variant.reason,
    );
  }

  @override
  Future<EvolutionOutcome> evaluate(
      EvolverVariant<OntologyVariant> candidate) async {
    final ConditionalEvalResult result =
        await service.evaluate(candidate.payload);
    return EvolutionOutcome(
      baselineScore: result.baselineScore,
      candidateScore: result.candidateScore,
      improvement: result.improvement,
      passed: result.passed,
    );
  }

  @override
  Future<bool> publish(EvolverVariant<OntologyVariant> candidate,
      {double threshold = 0.05}) async {
    return service.publish(candidate.payload, threshold: threshold);
  }
}
