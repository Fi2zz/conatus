import 'package:conatus_ontology/src/ontology/edit_validator.dart';
import 'package:conatus_ontology/src/ontology/edits.dart';
import 'package:conatus_ontology/src/ontology/layer.dart';
import 'package:conatus_ontology/src/ontology/node.dart';
import 'package:conatus_ontology/src/ontology/relation.dart';
import 'package:conatus_ontology/src/ontology/schema.dart';
import 'package:test/test.dart';

const TypedEditValidator _validator = TypedEditValidator(schema);

const OntologySchema schema = OntologySchema(
  nodeFields: <String, List<SchemaField>>{
    'term': <SchemaField>[
      SchemaField('name', SchemaFieldType.string, required: true),
      SchemaField('aliases', SchemaFieldType.stringArray),
    ],
  },
  allowedRelations: <String>{'is_a'},
  allowedReferences: <String>{'mapped_to'},
);

OntologyLayer _layer() => OntologyLayer(
      version: 'v0',
      nodes: <OntologyNode>[
        Term(
            id: 't1',
            createdAt: DateTime.utc(2026),
            name: '收入',
            definition: 'd'),
        Mapping(
            id: 'm1',
            createdAt: DateTime.utc(2026),
            termId: 't1',
            source: 's'),
      ],
      relations: const <SemanticRelation>[
        SemanticRelation(id: 'r1', fromTermId: 't1', toTermId: 't1', kind: 'is_a'),
      ],
      references: const <StructuralReference>[
        StructuralReference(id: 's1', fromId: 't1', toId: 'm1', kind: 'mapped_to'),
      ],
      schema: schema,
      createdAt: DateTime.utc(2026),
    );

void main() {
  group('AddNode', () {
    test('合法节点通过', () {
      final ValidationResult result = _validator.validate(
          AddNode(Term(
              id: 't2',
              createdAt: DateTime.utc(2026),
              name: '成本',
              definition: 'd')),
          _layer());
      expect(result.isValid, isTrue);
    });

    test('重复 id 拒绝', () {
      final ValidationResult result = _validator.validate(
          AddNode(Term(
              id: 't1',
              createdAt: DateTime.utc(2026),
              name: 'x',
              definition: 'd')),
          _layer());
      expect(result.isValid, isFalse);
    });

    test('schema 未定义的类型拒绝', () {
      final ValidationResult result = _validator.validate(
          AddNode(Constraint(
              id: 'c1',
              createdAt: DateTime.utc(2026),
              expression: 'x',
              scope: 't1')),
          _layer());
      expect(result.isValid, isFalse);
      expect(result.message, contains('未在 schema'));
    });
  });

  group('RemoveNode / UpdateNodeFields', () {
    test('删除存在的节点通过，删除缺失的拒绝', () {
      expect(
          _validator.validate(const RemoveNode('t1'), _layer()).isValid, isTrue);
      expect(
          _validator.validate(const RemoveNode('nope'), _layer()).isValid, isFalse);
    });

    test('更新合法字段通过', () {
      final ValidationResult result = _validator.validate(
          const UpdateNodeFields('t1', <String, Object?>{'name': '营业收入'}),
          _layer());
      expect(result.isValid, isTrue);
    });

    test('更新 schema 外字段拒绝', () {
      final ValidationResult result = _validator.validate(
          const UpdateNodeFields('t1', <String, Object?>{'nope': 1}), _layer());
      expect(result.isValid, isFalse);
      expect(result.message, contains('不在 schema'));
    });

    test('更新缺失节点拒绝', () {
      final ValidationResult result = _validator.validate(
          const UpdateNodeFields('nope', <String, Object?>{'name': 'x'}), _layer());
      expect(result.isValid, isFalse);
    });
  });

  group('AddRelation / AddReference', () {
    test('允许的关系且 Term 存在时通过', () {
      final ValidationResult result = _validator.validate(
          const AddRelation(SemanticRelation(
              id: 'r2', fromTermId: 't1', toTermId: 't1', kind: 'is_a')),
          _layer());
      expect(result.isValid, isTrue);
    });

    test('不允许的关系拒绝', () {
      final ValidationResult result = _validator.validate(
          const AddRelation(SemanticRelation(
              id: 'r2', fromTermId: 't1', toTermId: 't1', kind: 'part_of')),
          _layer());
      expect(result.isValid, isFalse);
      expect(result.message, contains('不被允许'));
    });

    test('引用缺失对象拒绝', () {
      final ValidationResult result = _validator.validate(
          const AddReference(StructuralReference(
              id: 's2', fromId: 'nope', toId: 'm1', kind: 'mapped_to')),
          _layer());
      expect(result.isValid, isFalse);
    });

    test('删除存在的关系/引用通过，缺失拒绝', () {
      expect(
          _validator.validate(const RemoveRelation('r1'), _layer()).isValid, isTrue);
      expect(
          _validator.validate(const RemoveRelation('nope'), _layer()).isValid, isFalse);
      expect(
          _validator.validate(const RemoveReference('s1'), _layer()).isValid, isTrue);
      expect(
          _validator.validate(const RemoveReference('nope'), _layer()).isValid, isFalse);
    });
  });

  group('MergeTerms / SplitTerm', () {
    test('合并两个存在的不同 Term 通过', () {
      final ValidationResult result = _validator.validate(
          const MergeTerms('t1', 't1'), _layer());
      expect(result.isValid, isFalse);
    });

    test('拆分产出空列表拒绝', () {
      final ValidationResult result = _validator.validate(
          const SplitTerm('t1', <Term>[]), _layer());
      expect(result.isValid, isFalse);
    });

    test('拆分缺失源拒绝', () {
      final ValidationResult result = _validator.validate(
          SplitTerm('nope', <Term>[
            Term(id: 'a', createdAt: DateTime.utc(2026), name: 'x', definition: 'd'),
          ]),
          _layer());
      expect(result.isValid, isFalse);
    });
  });

  group('TypedEdit JSON', () {
    test('各类型往返', () {
      final List<TypedEdit> edits = <TypedEdit>[
        AddNode(Term(
            id: 't9',
            createdAt: DateTime.utc(2026),
            name: 'n',
            definition: 'd')),
        const RemoveNode('t1'),
        const UpdateNodeFields('t1', <String, Object?>{'name': 'x'}),
        const AddRelation(SemanticRelation(
            id: 'r', fromTermId: 'a', toTermId: 'b', kind: 'is_a')),
        const RemoveRelation('r'),
        const AddReference(StructuralReference(
            id: 's', fromId: 'a', toId: 'b', kind: 'mapped_to')),
        const RemoveReference('s'),
        const MergeTerms('a', 'b'),
        SplitTerm('a', <Term>[
          Term(id: 'x', createdAt: DateTime.utc(2026), name: 'n', definition: 'd'),
        ]),
      ];
      for (final TypedEdit edit in edits) {
        final TypedEdit restored = TypedEdit.fromJson(edit.toJson());
        expect(restored.toJson(), edit.toJson());
      }
    });

    test('未知类型抛 ArgumentError', () {
      expect(
        () => TypedEdit.fromJson(<String, Object?>{'edit': 'nope'}),
        throwsArgumentError,
      );
    });
  });

  group('applyEdits', () {
    test('AddNode 生效', () {
      final OntologyLayer next = applyEdits(_layer(), <TypedEdit>[
        AddNode(Term(
            id: 't2',
            createdAt: DateTime.utc(2026),
            name: '成本',
            definition: 'd')),
      ]);
      expect(next.nodes, hasLength(3));
      expect(next.node('t2'), isNotNull);
    });

    test('RemoveNode 连同引用一起移除', () {
      final OntologyLayer next =
          applyEdits(_layer(), <TypedEdit>[const RemoveNode('t1')]);
      expect(next.node('t1'), isNull);
      expect(next.references, isEmpty);
    });

    test('UpdateNodeFields 更新字段', () {
      final OntologyLayer next = applyEdits(_layer(), <TypedEdit>[
        const UpdateNodeFields('t1', <String, Object?>{'name': '营业收入'}),
      ]);
      expect((next.node('t1')! as Term).name, '营业收入');
    });

    test('MergeTerms 移除源 Term 及相关边', () {
      final OntologyLayer next = applyEdits(_layer(), <TypedEdit>[
        const MergeTerms('t1', 't1'),
      ]);
      expect(next.node('t1'), isNull);
      expect(next.relations, isEmpty);
    });

    test('SplitTerm 用新 Terms 替换源', () {
      final OntologyLayer next = applyEdits(_layer(), <TypedEdit>[
        SplitTerm('t1', <Term>[
          Term(id: 'a', createdAt: DateTime.utc(2026), name: 'A', definition: 'd'),
          Term(id: 'b', createdAt: DateTime.utc(2026), name: 'B', definition: 'd'),
        ]),
      ]);
      expect(next.node('t1'), isNull);
      expect(next.node('a'), isNotNull);
      expect(next.node('b'), isNotNull);
    });
  });
}
