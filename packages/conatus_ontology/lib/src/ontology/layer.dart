/// 本体层：一个版本化的语义图。
library;

import 'node.dart';
import 'relation.dart';
import 'schema.dart';

/// 本体层。一个版本化的语义图。
class OntologyLayer {
  const OntologyLayer({
    required this.version,
    required this.nodes,
    required this.relations,
    required this.references,
    required this.schema,
    required this.createdAt,
    this.parentVersion,
  });

  factory OntologyLayer.fromJson(Map<String, Object?> json) => OntologyLayer(
        version: json['version']! as String,
        parentVersion: json['parentVersion'] as String?,
        nodes: <OntologyNode>[
          for (final Object? node in json['nodes']! as List)
            OntologyNode.fromJson(Map<String, Object?>.from(node! as Map)),
        ],
        relations: <SemanticRelation>[
          for (final Object? relation in json['relations']! as List)
            SemanticRelation.fromJson(
                Map<String, Object?>.from(relation! as Map)),
        ],
        references: <StructuralReference>[
          for (final Object? reference in json['references']! as List)
            StructuralReference.fromJson(
                Map<String, Object?>.from(reference! as Map)),
        ],
        schema: OntologySchema.defaults(),
        createdAt: DateTime.parse(json['createdAt']! as String),
      );

  final String version;
  final String? parentVersion;
  final List<OntologyNode> nodes;
  final List<SemanticRelation> relations;
  final List<StructuralReference> references;
  final OntologySchema schema;
  final DateTime createdAt;

  OntologyNode? node(String id) {
    for (final OntologyNode item in nodes) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<OntologyNode> nodesOfType(String type) =>
      <OntologyNode>[for (final OntologyNode item in nodes) if (item.type == type) item];

  List<Mapping> mappingsOf(String termId) => <Mapping>[
        for (final OntologyNode item in nodes)
          if (item is Mapping && item.termId == termId) item,
      ];

  List<Constraint> constraintsOf(String termId) => <Constraint>[
        for (final OntologyNode item in nodes)
          if (item is Constraint && item.scope == termId) item,
      ];

  /// 带新版本号复制（发布时沿用候选层内容）。
  OntologyLayer copyWithVersion(String newVersion) => OntologyLayer(
        version: newVersion,
        parentVersion: version,
        nodes: nodes,
        relations: relations,
        references: references,
        schema: schema,
        createdAt: DateTime.now(),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'version': version,
        'parentVersion': parentVersion,
        'nodes': <Map<String, Object?>>[for (final OntologyNode node in nodes) node.toJson()],
        'relations': <Map<String, Object?>>[
          for (final SemanticRelation relation in relations) relation.toJson(),
        ],
        'references': <Map<String, Object?>>[
          for (final StructuralReference reference in references)
            reference.toJson(),
        ],
        'createdAt': createdAt.toIso8601String(),
      };
}
