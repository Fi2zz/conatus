import 'package:conatus_ontology/src/ontology/layer.dart';
import 'package:conatus_ontology/src/ontology/node.dart';
import 'package:conatus_ontology/src/ontology/relation.dart';
import 'package:conatus_ontology/src/ontology/schema.dart';
import 'package:test/test.dart';

OntologyLayer _sampleLayer() {
  final DateTime now = DateTime.utc(2026);
  return OntologyLayer(
    version: 'ontology_v0',
    nodes: <OntologyNode>[
      Term(id: 't1', createdAt: now, name: '营业收入', definition: '主营收入'),
      Term(id: 't2', createdAt: now, name: '营业成本', definition: '主营成本'),
      Mapping(
          id: 'm1', createdAt: now, termId: 't1', source: 'sales.orders'),
      Constraint(
          id: 'c1',
          createdAt: now,
          expression: 'amount >= 0',
          scope: 't1'),
    ],
    relations: <SemanticRelation>[
      const SemanticRelation(
          id: 'r1', fromTermId: 't1', toTermId: 't2', kind: 'related_to'),
    ],
    references: <StructuralReference>[
      const StructuralReference(
          id: 's1', fromId: 't1', toId: 'm1', kind: 'mapped_to'),
    ],
    schema: OntologySchema.defaults(),
    createdAt: now,
  );
}

void main() {
  group('OntologyLayer 查询', () {
    final OntologyLayer layer = _sampleLayer();

    test('node 按 id 查找', () {
      expect(layer.node('t1'), isA<Term>());
      expect(layer.node('missing'), isNull);
    });

    test('nodesOfType 过滤类型', () {
      final List<OntologyNode> terms = layer.nodesOfType('term');
      expect(terms, hasLength(2));
      expect(layer.nodesOfType('mapping'), hasLength(1));
    });

    test('mappingsOf 按 termId 过滤', () {
      final List<Mapping> mappings = layer.mappingsOf('t1');
      expect(mappings, hasLength(1));
      expect(mappings.single.source, 'sales.orders');
      expect(layer.mappingsOf('t2'), isEmpty);
    });

    test('constraintsOf 按 scope 过滤', () {
      final List<Constraint> constraints = layer.constraintsOf('t1');
      expect(constraints, hasLength(1));
      expect(constraints.single.expression, 'amount >= 0');
    });
  });

  group('OntologyLayer JSON', () {
    test('往返', () {
      final OntologyLayer layer = _sampleLayer();
      final OntologyLayer restored = OntologyLayer.fromJson(layer.toJson());
      expect(restored.version, 'ontology_v0');
      expect(restored.parentVersion, isNull);
      expect(restored.nodes, hasLength(4));
      expect(restored.relations, hasLength(1));
      expect(restored.references, hasLength(1));
      expect(restored.node('t1'), isA<Term>());
    });

    test('copyWithVersion 保留内容并记录 parentVersion', () {
      final OntologyLayer layer = _sampleLayer();
      final OntologyLayer next = layer.copyWithVersion('ontology_v1');
      expect(next.version, 'ontology_v1');
      expect(next.parentVersion, 'ontology_v0');
      expect(next.nodes, hasLength(4));
      expect(next.node('t1'), isA<Term>());
    });
  });
}
