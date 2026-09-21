import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_ontology/src/evolver/attribution.dart';
import 'package:conatus_ontology/src/evolver/diagnosis.dart';
import 'package:conatus_ontology/src/ontology/edits.dart';
import 'package:conatus_ontology/src/ontology/layer.dart';
import 'package:conatus_ontology/src/ontology/node.dart';
import 'package:conatus_ontology/src/ontology/relation.dart';
import 'package:conatus_ontology/src/ontology/schema.dart';
import 'package:test/test.dart';

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

OntologyLayer _layer() => OntologyLayer(
      version: 'v0',
      nodes: <OntologyNode>[
        Term(id: 't1', createdAt: DateTime.utc(2026), name: '收入', definition: 'd'),
      ],
      relations: const <SemanticRelation>[],
      references: const <StructuralReference>[],
      schema: OntologySchema.defaults(),
      createdAt: DateTime.utc(2026),
    );

void main() {
  group('parseAttributions', () {
    test('解析归因数组', () {
      final List<Attribution> attributions = parseAttributions(
        '[{"target": "content", "errorType": "term_misunderstanding", '
        '"evidence": ["t1"], "suggestedEdits": []}]',
      );
      expect(attributions, hasLength(1));
      final Attribution attribution = attributions.single;
      expect(attribution.target, AttributionTarget.content);
      expect(attribution.errorType, 'term_misunderstanding');
      expect(attribution.evidence, <String>['t1']);
      expect(attribution.suggestedEdits, isEmpty);
    });

    test('未知 target 抛 FormatException', () {
      expect(
        () => parseAttributions(
            '[{"target": "nope", "errorType": "x", "evidence": [], "suggestedEdits": []}]'),
        throwsFormatException,
      );
    });
  });

  group('AttributionEngine', () {
    test('构造 prompt 并归因到正确层', () async {
      final _ScriptedProvider llm = _ScriptedProvider(<String>[
        '[{"target": "schema", "errorType": "constraint_violation", '
        '"evidence": ["t1"], "suggestedEdits": [{"edit": "add_node", "node": {"type": "term", "id": "t2", "createdAt": "2026-01-01T00:00:00.000Z", "name": "x", "definition": "d", "aliases": [], "evidence": []}}]}]',
      ]);
      final AttributionEngine engine = AttributionEngine(llm: llm);
      const SemanticDiagnosis diagnosis = SemanticDiagnosis(
          <SemanticError>[
            SemanticError(
                description: 'd',
                manifestation: 'm',
                fixDirection: 'f',
                traceIds: <String>['t1']),
          ]);
      final List<Attribution> result =
          await engine.attribute(diagnosis, _layer());
      expect(result, hasLength(1));
      expect(result.single.target, AttributionTarget.schema);
      expect(result.single.suggestedEdits.single, isA<AddNode>());
      expect(llm.requests.single.last.content, contains('归因'));
    });
  });
}
