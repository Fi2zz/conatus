/// 语义关系与结构引用：连接本体对象的有向边。
library;

/// 语义关系。连接两个 Term。
class SemanticRelation {
  const SemanticRelation({
    required this.id,
    required this.fromTermId,
    required this.toTermId,
    required this.kind,
  });

  factory SemanticRelation.fromJson(Map<String, Object?> json) =>
      SemanticRelation(
        id: json['id']! as String,
        fromTermId: json['fromTermId']! as String,
        toTermId: json['toTermId']! as String,
        kind: json['kind']! as String,
      );

  final String id;
  final String fromTermId;
  final String toTermId;
  final String kind; // is_a / part_of / derives_from / related_to

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'fromTermId': fromTermId,
        'toTermId': toTermId,
        'kind': kind,
      };
}

/// 结构引用。连接 Term 与 Mapping，或附加 Constraint / Evidence。
class StructuralReference {
  const StructuralReference({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.kind,
  });

  factory StructuralReference.fromJson(Map<String, Object?> json) =>
      StructuralReference(
        id: json['id']! as String,
        fromId: json['fromId']! as String,
        toId: json['toId']! as String,
        kind: json['kind']! as String,
      );

  final String id;
  final String fromId;
  final String toId;
  final String kind; // mapped_to / constrained_by / supported_by

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'fromId': fromId,
        'toId': toId,
        'kind': kind,
      };
}
