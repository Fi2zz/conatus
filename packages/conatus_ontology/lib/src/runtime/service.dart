/// OntologyService：本体层的浏览、解析、构建、进化与门控发布。
library;

import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart' hide MemoryStore;
import 'package:conatus_llm/conatus_llm.dart';

import '../builder/source.dart';
import '../evolver/evaluator.dart';
import '../evolver/evolver.dart';
import '../evolver/paired_evaluator.dart';
import '../ontology/layer.dart';
import '../store/database_store.dart';
import '../store/memory_store.dart';
import '../store/store.dart';
import 'browse.dart';
import 'resolve.dart';
import 'service_default.dart';

/// 本体事件（发布/拒绝的变更流）。
sealed class OntologyEvent {
  const OntologyEvent(this.variant);

  final OntologyVariant variant;
}

/// 本体发布成功。
class OntologyPublished extends OntologyEvent {
  const OntologyPublished(super.variant, this.layer);

  final OntologyLayer layer;
}

/// 本体候选被拒绝。
class OntologyRejected extends OntologyEvent {
  const OntologyRejected(super.variant, this.reason);

  final String reason;
}

/// 本体服务。
abstract class OntologyService {
  /// 当前生效层；未构建时为 `null`。
  OntologyLayer? get current;

  /// 已发布的所有版本。
  List<OntologyLayer> get versions;

  /// 从持久化存档恢复。
  Future<void> restore();

  /// 浏览本体层，返回节点摘要。
  Future<List<NodeSummary>> browse({String? type, String? query, int limit = 20});

  /// 解析术语（按名/别名），返回完整记录与关联对象。
  Future<ResolvedSemantics?> resolve(String term);

  /// 从数据源构建初始本体层。
  Future<OntologyLayer> build({
    required List<DataSource> sources,
    String version = 'ontology_v0',
  });

  /// 从轨迹进化：诊断 → 归因 → 生成 typed edits，产出候选。
  Future<OntologyVariant> evolve({
    required List<SessionEvent> trajectories,
    int minOccurrences = 3,
  });

  /// Backbone-conditional 配对评估候选。
  Future<ConditionalEvalResult> evaluate(OntologyVariant candidate);

  /// 发布或拒绝候选。
  Future<bool> publish(OntologyVariant candidate, {double threshold = 0.05});

  /// 回滚到指定版本。
  Future<void> rollback(String version);

  /// 变更流（发布/拒绝）。
  Stream<OntologyEvent> get changes;

  /// 释放资源。
  void dispose();
}

/// 装配本体服务；显式参数优先，缺省从上下文取服务。
///
/// 缺省依赖：`llm` / `approval` / `telemetry` / `database`（服务键
/// `llm` / `approval` / `telemetry` / `database`）。`evaluator` 缺省时
/// 仅 browse / resolve / build 可用，evolve / publish 抛 StateError。
OntologyService provideOntology(
  Context ctx, {
  OntologyService? ontology,
  OntologyStore? store,
  LlmProvider? llm,
  Evaluator? evaluator,
  List<BackboneConfig>? backbones,
  List<EvalCase> evalCases = const <EvalCase>[],
  Approval? approval,
  Telemetry? telemetry,
  Database? database,
}) {
  final OntologyService? provided = ontology ?? ctx.get<OntologyService>('ontology');
  if (provided != null) return provided;
  if (ctx.has('ontology')) {
    throw StateError('ontology 服务已注册但类型不符');
  }

  final LlmProvider? resolvedLlm = llm ?? ctx.get<LlmProvider>('llm');
  if (resolvedLlm == null) {
    throw StateError('缺少 llm 服务，请先 provideLlm 或传入 llm');
  }
  final Approval? resolvedApproval = approval ?? ctx.get<Approval>('approval');
  final Telemetry? resolvedTelemetry =
      telemetry ?? ctx.get<Telemetry>('telemetry');
  final Database? resolvedDatabase = database ?? ctx.get<Database>('database');
  final OntologyStore resolvedStore = store ??
      (resolvedDatabase != null
          ? DatabaseStore(database: resolvedDatabase)
          : MemoryStore());
  final List<BackboneConfig> resolvedBackbones = backbones ??
      const <BackboneConfig>[
        BackboneConfig(provider: 'default', model: 'default'),
      ];
  final Evaluator? resolvedEvaluator =
      evaluator ?? ctx.get<Evaluator>('evaluator');

  final PairedEvaluator pairedEvaluator = PairedEvaluator(
    backbones: resolvedBackbones,
    resolver: (BackboneConfig backbone) {
      final Evaluator? target = resolvedEvaluator;
      if (target == null) {
        throw StateError('缺少 evaluator，无法评估本体候选');
      }
      return target;
    },
  );

  final OntologyService service = DefaultOntologyService(
    llm: resolvedLlm,
    store: resolvedStore,
    pairedEvaluator: pairedEvaluator,
    evalCases: evalCases,
    approval: resolvedApproval,
    telemetry: resolvedTelemetry,
  );
  ctx.provide('ontology', service);
  return service;
}

/// 上下文访问器。
extension OntologyContext on Context {
  OntologyService get ontology => require<OntologyService>('ontology');
}
