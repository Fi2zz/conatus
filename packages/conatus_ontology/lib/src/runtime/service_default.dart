/// OntologyService 的默认实现：内存当前层 + 版本存档 + 门控发布。
library;

import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';

import '../builder/builder.dart';
import '../builder/source.dart';
import '../evolver/evaluator.dart';
import '../evolver/evolver.dart';
import '../evolver/paired_evaluator.dart';
import '../ontology/apply.dart';
import '../ontology/layer.dart';
import '../store/store.dart';
import 'browse.dart';
import 'resolve.dart';
import 'service.dart';

/// 默认本体服务。
///
/// `current` 为最近发布（或构建）的层；`versions` 来自 [OntologyStore]。
/// 发布经 backbone-conditional 配对评估 + 可选人类确认门控。
class DefaultOntologyService implements OntologyService {
  DefaultOntologyService({
    required LlmProvider llm,
    required OntologyStore store,
    required PairedEvaluator pairedEvaluator,
    required List<EvalCase> evalCases,
    Approval? approval,
    Telemetry? telemetry,
  })  : _llm = llm,
        _store = store,
        _pairedEvaluator = pairedEvaluator,
        _evalCases = evalCases,
        _approval = approval,
        _telemetry = telemetry;

  final LlmProvider _llm;
  final OntologyStore _store;
  final PairedEvaluator _pairedEvaluator;
  final List<EvalCase> _evalCases;
  final Approval? _approval;
  final Telemetry? _telemetry;

  final StreamController<OntologyEvent> _changes =
      StreamController<OntologyEvent>.broadcast();
  OntologyLayer? _current;

  @override
  OntologyLayer? get current => _current;

  @override
  List<OntologyLayer> get versions => _store.all;

  @override
  Stream<OntologyEvent> get changes => _changes.stream;

  @override
  Future<void> restore() async {
    await _store.load();
    if (_store.all.isNotEmpty) _current = _store.all.last;
  }

  @override
  Future<List<NodeSummary>> browse({
    String? type,
    String? query,
    int limit = 20,
  }) async {
    final OntologyLayer? layer = _current;
    if (layer == null) return const <NodeSummary>[];
    return browseLayer(layer, type: type, query: query, limit: limit);
  }

  @override
  Future<ResolvedSemantics?> resolve(String term) async {
    final OntologyLayer? layer = _current;
    if (layer == null) return null;
    return resolveSemantics(layer, term);
  }

  @override
  Future<OntologyLayer> build({
    required List<DataSource> sources,
    String version = 'ontology_v0',
  }) async {
    final BuildResult result =
        await buildOntology(_llm, sources, version: version);
    await _store.save(result.layer);
    _current = result.layer;
    return result.layer;
  }

  @override
  Future<OntologyVariant> evolve({
    required List<SessionEvent> trajectories,
    int minOccurrences = 3,
  }) async {
    final OntologyLayer? parent = _current;
    if (parent == null) throw StateError('当前无本体层，请先 build');
    final OntologyVariant? variant = await evolveVariant(
      llm: _llm,
      current: parent,
      trajectories: trajectories,
      minOccurrences: minOccurrences,
    );
    if (variant == null) throw StateError('轨迹不足，无法进化');
    return variant;
  }

  @override
  Future<ConditionalEvalResult> evaluate(OntologyVariant candidate) async {
    final OntologyLayer? parent = _current;
    if (parent == null) throw StateError('当前无本体层，请先 build');
    return _runPairedEval(parent, _apply(candidate));
  }

  @override
  Future<bool> publish(OntologyVariant candidate,
      {double threshold = 0.05}) async {
    final OntologyLayer? parent = _current;
    if (parent == null) throw StateError('当前无本体层，请先 build');
    final OntologyLayer candidateLayer = _apply(candidate);
    final ConditionalEvalResult result =
        await _runPairedEval(parent, candidateLayer);
    if (!result.passed || result.improvement < threshold) {
      _changes.add(OntologyRejected(candidate, '改进不足'));
      return false;
    }

    final Approval? gate = _approval;
    if (gate != null) {
      final bool approved = await gate.request(ApprovalRequest(
        id: 'publish-${DateTime.now().microsecondsSinceEpoch}',
        toolName: 'publish_ontology',
        arguments: <String, Object?>{
          'version': candidate.id,
          'improvement': result.improvement,
          'backbone': result.backbone.label,
          'editCount': candidate.edits.length,
        },
        description:
            '本体进化 +${(result.improvement * 100).toStringAsFixed(1)}%，确认发布？',
      ));
      if (!approved) {
        _changes.add(OntologyRejected(candidate, '用户拒绝'));
        return false;
      }
    }

    final String newVersion = 'ontology_v${versions.length}';
    final OntologyLayer published = candidateLayer.copyWithVersion(newVersion);
    await _store.save(published);
    _current = published;
    _changes.add(OntologyPublished(candidate, published));
    _telemetry?.emit(TelemetryEvent('ontology.published',
        data: <String, Object?>{
          'version': newVersion,
          'parent': candidate.parentVersion,
          'improvement': result.improvement,
        }));
    return true;
  }

  @override
  Future<void> rollback(String version) async {
    final OntologyLayer? target = _store.find(version);
    if (target == null) throw StateError('版本 "$version" 不存在');
    _current = target;
  }

  /// 配对评估 parent 与 candidate；结束后 current 恢复为 parent。
  Future<ConditionalEvalResult> _runPairedEval(
      OntologyLayer parent, OntologyLayer candidate) async {
    final ConditionalEvalResult result = await _pairedEvaluator.evaluate(
      parent: parent,
      candidate: candidate,
      cases: _evalCases,
      apply: (OntologyLayer layer) async {
        _current = layer;
      },
    );
    _current = parent;
    return result;
  }

  OntologyLayer _apply(OntologyVariant candidate) {
    final OntologyLayer parent = _current!;
    return applyEdits(parent, candidate.edits);
  }

  @override
  void dispose() {
    _changes.close();
  }
}
