/// 语义解析：按术语名/别名找到节点并返回关联对象。
library;

import '../ontology/layer.dart';
import '../ontology/node.dart';
import '../ontology/relation.dart';

/// 解析结果：目标节点 + 关联对象。
class ResolvedSemantics {
  const ResolvedSemantics({
    required this.node,
    required this.mappings,
    required this.constraints,
    required this.evidences,
    required this.relations,
    required this.references,
  });

  final OntologyNode node;
  final List<Mapping> mappings;
  final List<Constraint> constraints;
  final List<Evidence> evidences;
  final List<SemanticRelation> relations;
  final List<StructuralReference> references;

  Map<String, Object?> toJson() => <String, Object?>{
        'node': node.toJson(),
        'mappings': <Map<String, Object?>>[
          for (final Mapping mapping in mappings) mapping.toJson(),
        ],
        'constraints': <Map<String, Object?>>[
          for (final Constraint constraint in constraints) constraint.toJson(),
        ],
        'evidences': <Map<String, Object?>>[
          for (final Evidence evidence in evidences) evidence.toJson(),
        ],
        'relations': <Map<String, Object?>>[
          for (final SemanticRelation relation in relations) relation.toJson(),
        ],
        'references': <Map<String, Object?>>[
          for (final StructuralReference reference in references)
            reference.toJson(),
        ],
      };
}

/// 按术语名/别名查找并组装解析结果；找不到返回 `null`。
ResolvedSemantics? resolveSemantics(OntologyLayer layer, String term) {
  final OntologyNode? node = _findByTerm(layer, term);
  if (node == null) return null;
  final String id = node.id;

  return ResolvedSemantics(
    node: node,
    mappings: layer.mappingsOf(id),
    constraints: layer.constraintsOf(id),
    evidences: <Evidence>[
      for (final OntologyNode item in layer.nodes)
        if (item is Evidence && item.source == id) item,
    ],
    relations: <SemanticRelation>[
      for (final SemanticRelation relation in layer.relations)
        if (relation.fromTermId == id || relation.toTermId == id) relation,
    ],
    references: <StructuralReference>[
      for (final StructuralReference reference in layer.references)
        if (reference.fromId == id || reference.toId == id) reference,
    ],
  );
}

OntologyNode? _findByTerm(OntologyLayer layer, String term) {
  final String query = term.toLowerCase();
  for (final OntologyNode node in layer.nodes) {
    if (node is! Term) continue;
    if (node.name.toLowerCase() == query ||
        node.aliases.any((String alias) => alias.toLowerCase() == query)) {
      return node;
    }
  }
  return null;
}
