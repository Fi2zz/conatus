import 'package:conatus_ontology/src/ontology/node.dart';
import 'package:test/test.dart';

void main() {
  group('Term', () {
    test('JSON 往返', () {
      final Term term = Term(
        id: 't1',
        createdAt: DateTime.utc(2026),
        name: '营业收入',
        definition: '企业主营业务的收入',
        aliases: <String>['revenue', '营收'],
        domain: '财务',
        evidence: const <String>['e1'],
      );
      final Map<String, Object?> json = term.toJson();
      expect(json['type'], 'term');
      final Term restored = Term.fromJson(json);
      expect(restored.id, 't1');
      expect(restored.name, '营业收入');
      expect(restored.definition, '企业主营业务的收入');
      expect(restored.aliases, <String>['revenue', '营收']);
      expect(restored.domain, '财务');
      expect(restored.evidence, const <String>['e1']);
      expect(restored.createdAt, DateTime.utc(2026));
    });

    test('缺省字段', () {
      final Term term = Term(
        id: 't1',
        createdAt: DateTime.now(),
        name: 'n',
        definition: 'd',
      );
      expect(term.aliases, isEmpty);
      expect(term.domain, isNull);
      expect(term.evidence, isEmpty);
    });
  });

  group('Mapping', () {
    test('JSON 往返', () {
      final Mapping mapping = Mapping(
        id: 'm1',
        createdAt: DateTime.utc(2026, 1, 2),
        termId: 't1',
        source: 'sales.orders',
        expression: 'SUM(amount)',
      );
      final Mapping restored = Mapping.fromJson(mapping.toJson());
      expect(restored.termId, 't1');
      expect(restored.source, 'sales.orders');
      expect(restored.expression, 'SUM(amount)');
      expect(restored.type, 'mapping');
    });

    test('expression 可为空', () {
      final Mapping mapping = Mapping(
        id: 'm1',
        createdAt: DateTime.now(),
        termId: 't1',
        source: 'sales.orders',
      );
      final Mapping restored = Mapping.fromJson(mapping.toJson());
      expect(restored.expression, isNull);
    });
  });

  group('Constraint', () {
    test('JSON 往返', () {
      final Constraint constraint = Constraint(
        id: 'c1',
        createdAt: DateTime.utc(2026, 1, 3),
        expression: 'amount >= 0',
        scope: 't1',
        description: '金额非负',
      );
      final Constraint restored = Constraint.fromJson(constraint.toJson());
      expect(restored.expression, 'amount >= 0');
      expect(restored.scope, 't1');
      expect(restored.description, '金额非负');
      expect(restored.type, 'constraint');
    });
  });

  group('Evidence', () {
    test('JSON 往返', () {
      final Evidence evidence = Evidence(
        id: 'e1',
        createdAt: DateTime.utc(2026, 1, 4),
        source: 'sales.orders.amount',
        observedAt: DateTime.utc(2026),
        sample: 42,
      );
      final Evidence restored = Evidence.fromJson(evidence.toJson());
      expect(restored.source, 'sales.orders.amount');
      expect(restored.observedAt, DateTime.utc(2026));
      expect(restored.sample, 42);
      expect(restored.type, 'evidence');
    });
  });

  group('OntologyNode.fromJson', () {
    test('按 type 分发到子类', () {
      final Map<String, Object?> termJson = Term(
        id: 't1',
        createdAt: DateTime.now(),
        name: 'n',
        definition: 'd',
      ).toJson();
      expect(OntologyNode.fromJson(termJson), isA<Term>());
    });

    test('未知类型抛 ArgumentError', () {
      expect(
        () => OntologyNode.fromJson(<String, Object?>{'type': 'nope'}),
        throwsArgumentError,
      );
    });
  });
}
