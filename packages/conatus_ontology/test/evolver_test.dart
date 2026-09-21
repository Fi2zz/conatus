import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_ontology/src/evolver/evolver.dart';
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
      version: 'ontology_v0',
      nodes: <OntologyNode>[
        Term(id: 't1', createdAt: DateTime.utc(2026), name: '收入', definition: 'd'),
      ],
      relations: const <SemanticRelation>[],
      references: const <StructuralReference>[],
      schema: OntologySchema.defaults(),
      createdAt: DateTime.utc(2026),
    );

List<SessionEvent> _traces(int n) => List<SessionEvent>.generate(
      n,
      (int i) => SessionEvent.create(
          sessionId: 's1',
          type: kUserMessageEvent,
          seq: i,
          data: <String, Object?>{'text': '任务$i'}),
    );

void main() {
  group('evolveVariant', () {
    test('轨迹不足时返回 null 且不调 LLM', () async {
      final _ScriptedProvider llm = _ScriptedProvider(<String>[]);
      final OntologyVariant? variant = await evolveVariant(
        llm: llm,
        current: _layer(),
        trajectories: _traces(2),
      );
      expect(variant, isNull);
      expect(llm.requests, isEmpty);
    });

    test('走完诊断 → 归因 → 编辑全链路', () async {
      final _ScriptedProvider llm = _ScriptedProvider(<String>[
        '[{"description": "d", "manifestation": "m", "fixDirection": "f"}]',
        '[{"target": "content", "errorType": "x", "evidence": ["t1"], "suggestedEdits": []}]',
        '[{"edit": "add_node", "node": {"type": "term", "id": "t2", "createdAt": "2026-01-01T00:00:00.000Z", "name": "成本", "definition": "d", "aliases": [], "evidence": []}}]',
      ]);
      final OntologyVariant? variant = await evolveVariant(
        llm: llm,
        current: _layer(),
        trajectories: _traces(3),
      );
      expect(variant, isNotNull);
      expect(variant!.parentVersion, 'ontology_v0');
      expect(variant.edits, hasLength(1));
      expect(llm.requests, hasLength(3));
    });

    test('非法编辑抛 StateError', () async {
      final _ScriptedProvider llm = _ScriptedProvider(<String>[
        '[{"description": "d", "manifestation": "m", "fixDirection": "f"}]',
        '[{"target": "content", "errorType": "x", "evidence": ["t1"], "suggestedEdits": []}]',
        // 关系指向不存在的 Term。
        '[{"edit": "add_relation", "relation": {"id": "r1", "fromTermId": "nope", "toTermId": "nope2", "kind": "is_a"}}]',
      ]);
      await expectLater(
        evolveVariant(
          llm: llm,
          current: _layer(),
          trajectories: _traces(3),
        ),
        throwsStateError,
      );
    });
  });
}
