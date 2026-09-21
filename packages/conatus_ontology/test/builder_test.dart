import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_ontology/src/builder/builder.dart';
import 'package:conatus_ontology/src/builder/extractor.dart';
import 'package:conatus_ontology/src/builder/grounding.dart';
import 'package:conatus_ontology/src/builder/source.dart';
import 'package:conatus_ontology/src/ontology/node.dart';
import 'package:test/test.dart';

/// 按脚本回复的 LLM，并记录收到的请求。
class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.replies);

  final List<String> replies;
  final List<List<LlmMessage>> requests = <List<LlmMessage>>[];
  int _index = 0;

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    requests.add(messages);
    final String reply = replies[_index.clamp(0, replies.length - 1)];
    _index++;
    return LlmResult(content: reply, provider: name, model: 'test');
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

const List<DataSource> _sources = <DataSource>[
  DataSource(
    id: 'sales',
    name: '销售订单',
    columns: <DataColumn>[
      DataColumn(name: 'amount', type: 'number'),
      DataColumn(name: 'customer', type: 'string'),
    ],
    sampleRows: <Map<String, Object?>>[
      <String, Object?>{'amount': 100, 'customer': '甲'},
      <String, Object?>{'amount': 200, 'customer': '乙'},
    ],
  ),
];

void main() {
  group('parseTerms', () {
    test('解析 LLM 返回的 JSON 数组', () {
      final List<Term> terms = parseTerms(
        '[{"name": "营业收入", "definition": "主营收入", "aliases": ["revenue"], "domain": "财务"}]',
        DateTime.utc(2026),
      );
      expect(terms, hasLength(1));
      expect(terms.single.name, '营业收入');
      expect(terms.single.definition, '主营收入');
      expect(terms.single.aliases, <String>['revenue']);
      expect(terms.single.domain, '财务');
    });

    test('容忍 markdown 代码围栏', () {
      final List<Term> terms = parseTerms(
        '```json\n[{"name": "x", "definition": "d"}]\n```',
        DateTime.utc(2026),
      );
      expect(terms, hasLength(1));
    });

    test('非法 JSON 抛 FormatException', () {
      expect(() => parseTerms('不是JSON', DateTime.utc(2026)),
          throwsFormatException);
    });
  });

  group('extractCandidates', () {
    test('构造 prompt 并返回候选', () async {
      final _ScriptedProvider llm = _ScriptedProvider(
          <String>['[{"name": "营业收入", "definition": "d"}]']);
      final List<Term> terms = await extractCandidates(llm, _sources);
      expect(terms, hasLength(1));
      expect(llm.requests, hasLength(1));
      expect(llm.requests.single.first.role, 'system');
      expect(llm.requests.single.last.content, contains('销售订单'));
    });
  });

  group('groundTerm', () {
    test('名称匹配列名时产生可执行映射', () {
      final Term term = Term(
        id: 't1',
        createdAt: DateTime.utc(2026),
        name: '订单金额',
        definition: 'd',
        aliases: <String>['amount'],
      );
      final GroundingResult result = groundTerm(term, _sources);
      expect(result.grounded, isTrue);
      expect(result.mappings, hasLength(1)); // amount 列命中别名
      expect(result.mappings.single.source, 'sales.amount');
      expect(result.constraints, hasLength(1));
      expect(result.evidences, hasLength(1));
    });

    test('术语名命中表名时产生表级映射', () {
      final Term term = Term(
        id: 't1',
        createdAt: DateTime.utc(2026),
        name: '销售订单',
        definition: 'd',
      );
      final GroundingResult result = groundTerm(term, _sources);
      expect(result.grounded, isTrue);
      expect(result.mappings, hasLength(1));
      expect(result.mappings.single.source, 'sales');
      expect(result.mappings.single.expression, isNull);
    });

    test('无匹配时拒绝', () {
      final Term term = Term(
        id: 't1',
        createdAt: DateTime.utc(2026),
        name: '完全无关概念',
        definition: 'd',
      );
      final GroundingResult result = groundTerm(term, _sources);
      expect(result.grounded, isFalse);
      expect(result.mappings, isEmpty);
    });
  });

  group('constraintHolds', () {
    test('非空约束在无 null 样本下成立', () {
      expect(
        constraintHolds(
          Constraint(
            id: 'c1',
            createdAt: DateTime.utc(2026),
            expression: 'amount is not null',
            scope: 't1',
          ),
          _sources,
        ),
        isTrue,
      );
    });

    test('含 null 样本时非空约束不成立', () {
      const List<DataSource> withNull = <DataSource>[
        DataSource(
          id: 's',
          name: 's',
          columns: <DataColumn>[DataColumn(name: 'amount', type: 'number')],
          sampleRows: <Map<String, Object?>>[
            <String, Object?>{'amount': null},
          ],
        ),
      ];
      expect(
        constraintHolds(
          Constraint(
            id: 'c1',
            createdAt: DateTime.utc(2026),
            expression: 'amount is not null',
            scope: 't1',
          ),
          withNull,
        ),
        isFalse,
      );
    });

    test('未知表达式不成立', () {
      expect(
        constraintHolds(
          Constraint(
            id: 'c1',
            createdAt: DateTime.utc(2026),
            expression: 'amount weird',
            scope: 't1',
          ),
          _sources,
        ),
        isFalse,
      );
    });
  });

  group('buildOntology', () {
    test('接地术语进入层，未接地被拒绝', () async {
      final _ScriptedProvider llm = _ScriptedProvider(<String>[
        '[{"name": "订单金额", "definition": "d", "aliases": ["amount"]}, {"name": "无关概念", "definition": "d"}]',
      ]);
      final BuildResult result = await buildOntology(llm, _sources);
      expect(result.grounded, hasLength(1));
      expect(result.rejected, hasLength(1));
      expect(result.layer.version, 'ontology_v0');
      expect(result.layer.nodesOfType('term'), hasLength(1));
      expect(result.layer.nodesOfType('mapping'), isNotEmpty);
      expect(result.layer.nodesOfType('constraint'), isNotEmpty);
      expect(result.layer.nodesOfType('evidence'), isNotEmpty);
      expect(
        result.layer.references
            .where((r) => r.kind == 'mapped_to'),
        isNotEmpty,
      );
    });

    test('全不接地时产出空层', () async {
      final _ScriptedProvider llm =
          _ScriptedProvider(<String>['[{"name": "无关概念", "definition": "d"}]']);
      final BuildResult result = await buildOntology(llm, _sources);
      expect(result.grounded, isEmpty);
      expect(result.layer.nodes, isEmpty);
    });
  });

  group('DataSource JSON', () {
    test('往返', () {
      final DataSource restored = DataSource.fromJson(_sources.first.toJson());
      expect(restored.id, 'sales');
      expect(restored.columnNames, contains('amount'));
      expect(restored.sampleRows, hasLength(2));
    });
  });
}
