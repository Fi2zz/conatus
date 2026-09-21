/// 构建流程：从工作负载提取候选 → 接地验证 → 组装 ontology_v0。
library;

import 'package:conatus_llm/conatus_llm.dart';

import '../ontology/layer.dart';
import '../ontology/node.dart';
import '../ontology/relation.dart';
import '../ontology/schema.dart';
import 'extractor.dart';
import 'grounding.dart';
import 'source.dart';

/// 从数据源构建初始本体层。
///
/// 只有通过接地验证（至少一个可执行映射）的术语才进入本体；
/// 未接地术语作为候选返回，由调用方决定是否保留。
Future<BuildResult> buildOntology(
  LlmProvider llm,
  List<DataSource> sources, {
  String version = 'ontology_v0',
}) async {
  final DateTime now = DateTime.now();
  final List<Term> candidates = await extractCandidates(llm, sources);

  final List<OntologyNode> nodes = <OntologyNode>[];
  final List<StructuralReference> references = <StructuralReference>[];
  final List<Term> grounded = <Term>[];
  final List<Term> rejected = <Term>[];

  for (final Term term in candidates) {
    final GroundingResult result = groundTerm(term, sources);
    if (!result.grounded) {
      rejected.add(term);
      continue;
    }
    grounded.add(term);
    nodes
      ..add(term)
      ..addAll(result.mappings)
      ..addAll(result.constraints)
      ..addAll(result.evidences);
    for (final Mapping mapping in result.mappings) {
      references.add(StructuralReference(
        id: 'ref-${references.length + 1}',
        fromId: term.id,
        toId: mapping.id,
        kind: 'mapped_to',
      ));
    }
    for (final Constraint constraint in result.constraints) {
      references.add(StructuralReference(
        id: 'ref-${references.length + 1}',
        fromId: term.id,
        toId: constraint.id,
        kind: 'constrained_by',
      ));
    }
    for (final Evidence evidence in result.evidences) {
      references.add(StructuralReference(
        id: 'ref-${references.length + 1}',
        fromId: term.id,
        toId: evidence.id,
        kind: 'supported_by',
      ));
    }
  }

  final OntologyLayer layer = OntologyLayer(
    version: version,
    nodes: nodes,
    relations: const <SemanticRelation>[],
    references: references,
    schema: OntologySchema.defaults(),
    createdAt: now,
  );
  return BuildResult(layer: layer, grounded: grounded, rejected: rejected);
}

/// 构建结果：产出层 + 接地/未接地的术语清单。
class BuildResult {
  const BuildResult({
    required this.layer,
    required this.grounded,
    required this.rejected,
  });

  final OntologyLayer layer;
  final List<Term> grounded;
  final List<Term> rejected;
}
