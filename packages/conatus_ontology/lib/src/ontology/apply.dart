/// 类型化编辑的应用：把一组编辑作用到层，产出新层。
library;

import 'edits.dart';
import 'layer.dart';
import 'node.dart';
import 'relation.dart';

/// 把一组编辑应用到层，产出新层（发布时用）。
OntologyLayer applyEdits(OntologyLayer layer, List<TypedEdit> edits) {
  final List<OntologyNode> nodes = <OntologyNode>[...layer.nodes];
  final List<SemanticRelation> relations = <SemanticRelation>[...layer.relations];
  final List<StructuralReference> references =
      <StructuralReference>[...layer.references];

  for (final TypedEdit edit in edits) {
    switch (edit) {
      case AddNode(:final OntologyNode node):
        nodes.add(node);
      case RemoveNode(:final String nodeId):
        nodes.removeWhere((OntologyNode n) => n.id == nodeId);
        references.removeWhere((StructuralReference r) =>
            r.fromId == nodeId || r.toId == nodeId);
      case UpdateNodeFields(:final String nodeId, :final fields):
        _updateNodeFields(nodes, nodeId, fields);
      case AddRelation(:final SemanticRelation relation):
        relations.add(relation);
      case RemoveRelation(:final String relationId):
        relations.removeWhere((SemanticRelation r) => r.id == relationId);
      case AddReference(:final StructuralReference reference):
        references.add(reference);
      case RemoveReference(:final String referenceId):
        references.removeWhere(
            (StructuralReference r) => r.id == referenceId);
      case MergeTerms(:final String sourceTermId, :final String targetTermId):
        _mergeTerms(nodes, relations, references, sourceTermId, targetTermId);
      case SplitTerm(:final String sourceTermId, :final List<Term> newTerms):
        _splitTerm(nodes, relations, references, sourceTermId, newTerms);
    }
  }

  return OntologyLayer(
    version: layer.version,
    parentVersion: layer.parentVersion,
    nodes: nodes,
    relations: relations,
    references: references,
    schema: layer.schema,
    createdAt: layer.createdAt,
  );
}

void _updateNodeFields(
    List<OntologyNode> nodes, String nodeId, Map<String, Object?> fields) {
  final int index = nodes.indexWhere((OntologyNode n) => n.id == nodeId);
  if (index < 0) return;
  final OntologyNode original = nodes[index];
  final Map<String, Object?> json = original.toJson()..addAll(fields);
  nodes[index] = OntologyNode.fromJson(json);
}

void _mergeTerms(
    List<OntologyNode> nodes,
    List<SemanticRelation> relations,
    List<StructuralReference> references,
    String sourceTermId,
    String targetTermId) {
  nodes.removeWhere((OntologyNode n) => n.id == sourceTermId);
  relations.removeWhere((SemanticRelation r) =>
      r.fromTermId == sourceTermId || r.toTermId == sourceTermId);
  references.removeWhere((StructuralReference r) => r.fromId == sourceTermId);
}

void _splitTerm(
    List<OntologyNode> nodes,
    List<SemanticRelation> relations,
    List<StructuralReference> references,
    String sourceTermId,
    List<Term> newTerms) {
  nodes.removeWhere((OntologyNode n) => n.id == sourceTermId);
  nodes.addAll(newTerms);
  relations.removeWhere((SemanticRelation r) =>
      r.fromTermId == sourceTermId || r.toTermId == sourceTermId);
  references.removeWhere((StructuralReference r) => r.fromId == sourceTermId);
}
