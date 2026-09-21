/// 语义浏览：按类型/关键词过滤本体节点，返回紧凑摘要。
library;

import '../ontology/layer.dart';
import '../ontology/node.dart';

/// 节点摘要（供 browse 与 MCP 工具返回，不携带完整记录）。
class NodeSummary {
  const NodeSummary({
    required this.id,
    required this.type,
    required this.label,
    this.snippet,
  });

  factory NodeSummary.of(OntologyNode node) => NodeSummary(
        id: node.id,
        type: node.type,
        label: _labelOf(node),
        snippet: _snippetOf(node),
      );

  final String id;
  final String type;
  final String label;
  final String? snippet;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'type': type,
        'label': label,
        'snippet': snippet,
      };
}

/// 浏览当前层：可选 type 过滤、query 关键词匹配、limit 截断。
List<NodeSummary> browseLayer(
  OntologyLayer layer, {
  String? type,
  String? query,
  int limit = 20,
}) {
  final List<OntologyNode> matched = <OntologyNode>[
    for (final OntologyNode node in layer.nodes)
      if (_matches(node, type: type, query: query)) node,
  ];
  final int end = matched.length < limit ? matched.length : limit;
  return <NodeSummary>[
    for (final OntologyNode node in matched.sublist(0, end))
      NodeSummary.of(node),
  ];
}

bool _matches(OntologyNode node, {String? type, String? query}) {
  if (type != null && node.type != type) return false;
  if (query == null || query.isEmpty) return true;
  final String text = _searchText(node).toLowerCase();
  return text.contains(query.toLowerCase());
}

String _searchText(OntologyNode node) {
  final StringBuffer buffer = StringBuffer(node.id);
  switch (node) {
    case Term():
      buffer.write(' ${node.name} ${node.definition} ${node.aliases.join(' ')}');
    case Mapping():
      buffer.write(' ${node.termId} ${node.source}');
    case Constraint():
      buffer.write(' ${node.expression} ${node.scope}');
    case Evidence():
      buffer.write(' ${node.source}');
  }
  return buffer.toString();
}

String _labelOf(OntologyNode node) {
  return switch (node) {
    Term() => node.name,
    Mapping() => node.source,
    Constraint() => node.expression,
    Evidence() => node.source,
  };
}

String? _snippetOf(OntologyNode node) {
  return switch (node) {
    Term() => node.definition,
    Mapping() => node.termId,
    Constraint() => node.description,
    Evidence() => node.observedAt.toIso8601String(),
  };
}
