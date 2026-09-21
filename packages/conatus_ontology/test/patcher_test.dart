import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_ontology/src/evolver/attribution.dart';
import 'package:conatus_ontology/src/evolver/patcher.dart';
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
  group('parseTypedEdits', () {
    test('解析 add_node', () {
      final List<TypedEdit> edits = parseTypedEdits(
        '[{"edit": "add_node", "node": {"type": "term", "id": "t2", '
        '"createdAt": "2026-01-01T00:00:00.000Z", "name": "x", '
        '"definition": "d", "aliases": [], "evidence": []}}]',
      );
      expect(edits, hasLength(1));
      expect(edits.single, isA<AddNode>());
      expect((edits.single as AddNode).node, isA<Term>());
    });

    test('非法 JSON 抛 FormatException', () {
      expect(() => parseTypedEdits('nope'), throwsFormatException);
    });
  });

  group('generateEdits', () {
    test('构造 prompt 并解析编辑', () async {
      final _ScriptedProvider llm = _ScriptedProvider(<String>[
        '[{"edit": "remove_node", "nodeId": "t1"}]',
      ]);
      final List<TypedEdit> edits = await generateEdits(
        llm,
        const <Attribution>[
          Attribution(
            target: AttributionTarget.content,
            errorType: 'term_misunderstanding',
            evidence: <String>['t1'],
            suggestedEdits: <TypedEdit>[],
          ),
        ],
        _layer(),
      );
      expect(edits, hasLength(1));
      expect(edits.single, isA<RemoveNode>());
      expect(llm.requests.single.last.content, contains('add_node'));
    });
  });
}
