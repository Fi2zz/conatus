/// OntologyService 的默认实现：内存当前层 + 版本存档。
library;

import 'dart:async';

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';

import '../builder/builder.dart';
import '../builder/source.dart';
import '../evolver/evaluator.dart';
import '../evolver/evolver.dart';
import '../ontology/layer.dart';
import '../store/store.dart';
import 'browse.dart';
import 'resolve.dart';
import 'service.dart';

/// 默认本体服务。
///
/// `current` 为最近发布（或构建）的层；`versions` 来自 [OntologyStore]。
class DefaultOntologyService implements OntologyService {
  DefaultOntologyService({
    required LlmProvider llm,
    required OntologyStore store,
  })  : _llm = llm,
        _store = store;

  final LlmProvider _llm;
  final OntologyStore _store;

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
  }) {
    throw UnimplementedError('evolve 在 Phase 7 实现');
  }

  @override
  Future<ConditionalEvalResult> evaluate(OntologyVariant candidate) {
    throw UnimplementedError('evaluate 在 Phase 7 实现');
  }

  @override
  Future<bool> publish(OntologyVariant candidate, {double threshold = 0.05}) {
    throw UnimplementedError('publish 在 Phase 7 实现');
  }

  @override
  Future<void> rollback(String version) {
    throw UnimplementedError('rollback 在 Phase 7 实现');
  }

  @override
  void dispose() {
    _changes.close();
  }
}
