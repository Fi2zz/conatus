/// 类型化编辑：本体进化的 9 种编辑操作，以及应用到层的函数。
library;

import 'layer.dart';
import 'node.dart';
import 'relation.dart';

/// 类型化编辑。论文定义的编辑操作。
sealed class TypedEdit {
  const TypedEdit();

  factory TypedEdit.fromJson(Map<String, Object?> json) {
    final String kind = json['edit']! as String;
    return switch (kind) {
      'add_node' => AddNode(OntologyNode.fromJson(
          Map<String, Object?>.from(json['node']! as Map))),
      'remove_node' => RemoveNode(json['nodeId']! as String),
      'update_node_fields' => UpdateNodeFields(
          json['nodeId']! as String,
          Map<String, Object?>.from(json['fields']! as Map)),
      'add_relation' => AddRelation(SemanticRelation.fromJson(
          Map<String, Object?>.from(json['relation']! as Map))),
      'remove_relation' => RemoveRelation(json['relationId']! as String),
      'add_reference' => AddReference(StructuralReference.fromJson(
          Map<String, Object?>.from(json['reference']! as Map))),
      'remove_reference' => RemoveReference(json['referenceId']! as String),
      'merge_terms' => MergeTerms(
          json['sourceTermId']! as String, json['targetTermId']! as String),
      'split_term' => SplitTerm(
          json['sourceTermId']! as String,
          <Term>[
            for (final Object? term in json['newTerms']! as List)
              Term.fromJson(Map<String, Object?>.from(term! as Map)),
          ]),
      _ => throw ArgumentError('未知编辑类型: $kind'),
    };
  }

  Map<String, Object?> toJson();
}

/// 添加节点。
class AddNode extends TypedEdit {
  const AddNode(this.node);

  final OntologyNode node;

  @override
  Map<String, Object?> toJson() =>
      <String, Object?>{'edit': 'add_node', 'node': node.toJson()};
}

/// 删除节点。
class RemoveNode extends TypedEdit {
  const RemoveNode(this.nodeId);

  final String nodeId;

  @override
  Map<String, Object?> toJson() =>
      <String, Object?>{'edit': 'remove_node', 'nodeId': nodeId};
}

/// 更新节点字段。
class UpdateNodeFields extends TypedEdit {
  const UpdateNodeFields(this.nodeId, this.fields);

  final String nodeId;
  final Map<String, Object?> fields;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'edit': 'update_node_fields',
        'nodeId': nodeId,
        'fields': fields,
      };
}

/// 添加语义关系。
class AddRelation extends TypedEdit {
  const AddRelation(this.relation);

  final SemanticRelation relation;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'edit': 'add_relation',
        'relation': relation.toJson(),
      };
}

/// 删除语义关系。
class RemoveRelation extends TypedEdit {
  const RemoveRelation(this.relationId);

  final String relationId;

  @override
  Map<String, Object?> toJson() =>
      <String, Object?>{'edit': 'remove_relation', 'relationId': relationId};
}

/// 添加结构引用。
class AddReference extends TypedEdit {
  const AddReference(this.reference);

  final StructuralReference reference;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'edit': 'add_reference',
        'reference': reference.toJson(),
      };
}

/// 删除结构引用。
class RemoveReference extends TypedEdit {
  const RemoveReference(this.referenceId);

  final String referenceId;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'edit': 'remove_reference',
        'referenceId': referenceId,
      };
}

/// 合并两个 Term。
class MergeTerms extends TypedEdit {
  const MergeTerms(this.sourceTermId, this.targetTermId);

  final String sourceTermId;
  final String targetTermId;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'edit': 'merge_terms',
        'sourceTermId': sourceTermId,
        'targetTermId': targetTermId,
      };
}

/// 拆分一个 Term。
class SplitTerm extends TypedEdit {
  const SplitTerm(this.sourceTermId, this.newTerms);

  final String sourceTermId;
  final List<Term> newTerms;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'edit': 'split_term',
        'sourceTermId': sourceTermId,
        'newTerms': <Map<String, Object?>>[
          for (final Term term in newTerms) term.toJson(),
        ],
      };
}

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
        relations.removeWhere(
            (SemanticRelation r) => r.id == relationId);
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
  references.removeWhere(
      (StructuralReference r) => r.fromId == sourceTermId);
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
  references.removeWhere(
      (StructuralReference r) => r.fromId == sourceTermId);
}
