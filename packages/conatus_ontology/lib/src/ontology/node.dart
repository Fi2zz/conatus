/// 本体节点：Term / Mapping / Constraint / Evidence 的公共类型与 JSON 往返。
library;

/// 本体节点。四种类型。
sealed class OntologyNode {
  const OntologyNode({
    required this.id,
    required this.createdAt,
    this.evidence = const <String>[],
  });

  factory OntologyNode.fromJson(Map<String, Object?> json) {
    return switch (json['type']) {
      'term' => Term.fromJson(json),
      'mapping' => Mapping.fromJson(json),
      'constraint' => Constraint.fromJson(json),
      'evidence' => Evidence.fromJson(json),
      _ => throw ArgumentError('未知节点类型: ${json['type']}'),
    };
  }

  final String id;
  final DateTime createdAt;
  final List<String> evidence;

  String get type;
  Map<String, Object?> toJson();
}

/// 术语。领域的核心概念。
class Term extends OntologyNode {
  const Term({
    required super.id,
    required super.createdAt,
    required this.name,
    required this.definition,
    this.aliases = const <String>[],
    this.domain,
    super.evidence,
  });

  factory Term.fromJson(Map<String, Object?> json) => Term(
        id: json['id']! as String,
        createdAt: DateTime.parse(json['createdAt']! as String),
        name: json['name']! as String,
        definition: json['definition']! as String,
        aliases: <String>[
          for (final Object? alias in json['aliases']! as List) alias! as String,
        ],
        domain: json['domain'] as String?,
        evidence: _stringList(json['evidence']),
      );

  final String name;
  final String definition;
  final List<String> aliases;
  final String? domain;

  @override
  String get type => 'term';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': type,
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'name': name,
        'definition': definition,
        'aliases': aliases,
        'domain': domain,
        'evidence': evidence,
      };
}

/// 映射。术语与数据源的对应关系。
class Mapping extends OntologyNode {
  const Mapping({
    required super.id,
    required super.createdAt,
    required this.termId,
    required this.source,
    this.expression,
    super.evidence,
  });

  factory Mapping.fromJson(Map<String, Object?> json) => Mapping(
        id: json['id']! as String,
        createdAt: DateTime.parse(json['createdAt']! as String),
        termId: json['termId']! as String,
        source: json['source']! as String,
        expression: json['expression'] as String?,
        evidence: _stringList(json['evidence']),
      );

  final String termId;
  final String source;
  final String? expression;

  @override
  String get type => 'mapping';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': type,
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'termId': termId,
        'source': source,
        'expression': expression,
        'evidence': evidence,
      };
}

/// 约束。业务规则或数据约束。
class Constraint extends OntologyNode {
  const Constraint({
    required super.id,
    required super.createdAt,
    required this.expression,
    required this.scope,
    this.description,
    super.evidence,
  });

  factory Constraint.fromJson(Map<String, Object?> json) => Constraint(
        id: json['id']! as String,
        createdAt: DateTime.parse(json['createdAt']! as String),
        expression: json['expression']! as String,
        scope: json['scope']! as String,
        description: json['description'] as String?,
        evidence: _stringList(json['evidence']),
      );

  final String expression;
  final String scope;
  final String? description;

  @override
  String get type => 'constraint';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': type,
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'expression': expression,
        'scope': scope,
        'description': description,
        'evidence': evidence,
      };
}

/// 证据。支持某个本体对象的观察。
class Evidence extends OntologyNode {
  const Evidence({
    required super.id,
    required super.createdAt,
    required this.source,
    required this.observedAt,
    this.sample,
    super.evidence,
  });

  factory Evidence.fromJson(Map<String, Object?> json) => Evidence(
        id: json['id']! as String,
        createdAt: DateTime.parse(json['createdAt']! as String),
        source: json['source']! as String,
        observedAt: DateTime.parse(json['observedAt']! as String),
        sample: json['sample'],
        evidence: _stringList(json['evidence']),
      );

  final String source;
  final DateTime observedAt;
  final Object? sample;

  @override
  String get type => 'evidence';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': type,
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'source': source,
        'observedAt': observedAt.toIso8601String(),
        'sample': sample,
        'evidence': evidence,
      };
}

List<String> _stringList(Object? value) => <String>[
      for (final Object? item in value! as List) item! as String,
    ];
