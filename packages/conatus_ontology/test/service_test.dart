import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart' hide MemoryStore;
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_ontology/src/builder/source.dart';
import 'package:conatus_ontology/src/evolver/evaluator.dart';
import 'package:conatus_ontology/src/evolver/paired_evaluator.dart';
import 'package:conatus_ontology/src/ontology/layer.dart';
import 'package:conatus_ontology/src/ontology/node.dart';
import 'package:conatus_ontology/src/ontology/relation.dart';
import 'package:conatus_ontology/src/ontology/schema.dart';
import 'package:conatus_ontology/src/runtime/browse.dart';
import 'package:conatus_ontology/src/runtime/manifest.dart';
import 'package:conatus_ontology/src/runtime/resolve.dart';
import 'package:conatus_ontology/src/runtime/service_default.dart';
import 'package:conatus_ontology/src/store/memory_store.dart';
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

const List<DataSource> _sources = <DataSource>[
  DataSource(
    id: 'sales',
    name: '销售订单',
    columns: <DataColumn>[
      DataColumn(name: 'amount', type: 'number'),
    ],
    sampleRows: <Map<String, Object?>>[
      <String, Object?>{'amount': 100},
    ],
  ),
];

DefaultOntologyService _service(_ScriptedProvider llm) => DefaultOntologyService(
      llm: llm,
      store: MemoryStore(),
      pairedEvaluator: PairedEvaluator(
        backbones: const <BackboneConfig>[],
        resolver: (BackboneConfig b) => Evaluator(
            run: (String input) async => const AgentTurn(
                reply: 'ok', messages: <LlmMessage>[], steps: <AgentStep>[])),
      ),
      evalCases: const <EvalCase>[],
    );

void main() {
  group('build / browse / resolve', () {
    test('构建后 current 生效，browse 返回摘要', () async {
      final _ScriptedProvider llm = _ScriptedProvider(<String>[
        '[{"name": "订单金额", "definition": "d", "aliases": ["amount"]}]',
      ]);
      final DefaultOntologyService service = _service(llm);
      final OntologyLayer layer =
          await service.build(sources: _sources);

      expect(service.current, same(layer));
      expect(service.versions, hasLength(1));

      final List<NodeSummary> summaries =
          await service.browse(type: 'term');
      expect(summaries, hasLength(1));
      expect(summaries.single.label, '订单金额');

      final ResolvedSemantics? resolved = await service.resolve('订单金额');
      expect(resolved, isNotNull);
      expect(resolved!.mappings, hasLength(1));
      expect(resolved.mappings.single.source, 'sales.amount');

      expect(await service.resolve('missing'), isNull);
    });

    test('未构建时 browse/resolve 返回空', () async {
      final DefaultOntologyService service = _service(_ScriptedProvider(<String>[]));
      expect(await service.browse(), isEmpty);
      expect(await service.resolve('x'), isNull);
      await expectLater(service.evolve(trajectories: const <SessionEvent>[]),
          throwsStateError);
    });
  });

  group('restore', () {
    test('从存档恢复最后版本为 current', () async {
      final _ScriptedProvider llm = _ScriptedProvider(<String>[
        '[{"name": "订单金额", "definition": "d", "aliases": ["amount"]}]',
      ]);
      final MemoryStore store = MemoryStore();
      final DefaultOntologyService first = DefaultOntologyService(
        llm: llm,
        store: store,
        pairedEvaluator: PairedEvaluator(
          backbones: const <BackboneConfig>[],
          resolver: (BackboneConfig b) => Evaluator(
              run: (String input) async => const AgentTurn(
                  reply: 'ok',
                  messages: <LlmMessage>[],
                  steps: <AgentStep>[])),
        ),
        evalCases: const <EvalCase>[],
      );
      await first.build(sources: _sources);

      final DefaultOntologyService second = DefaultOntologyService(
        llm: _ScriptedProvider(<String>[]),
        store: store,
        pairedEvaluator: PairedEvaluator(
          backbones: const <BackboneConfig>[],
          resolver: (BackboneConfig b) => Evaluator(
              run: (String input) async => const AgentTurn(
                  reply: 'ok',
                  messages: <LlmMessage>[],
                  steps: <AgentStep>[])),
        ),
        evalCases: const <EvalCase>[],
      );
      expect(second.current, isNull);
      await second.restore();
      expect(second.current, isNotNull);
      expect(second.current!.version, 'ontology_v0');
    });
  });

  group('buildManifest', () {
    test('生成紧凑清单', () {
      final OntologyLayer layer = OntologyLayer(
        version: 'ontology_v0',
        nodes: <OntologyNode>[
          Term(
              id: 't1',
              createdAt: DateTime.utc(2026),
              name: '收入',
              definition: '主营收入'),
        ],
        relations: const <SemanticRelation>[],
        references: const <StructuralReference>[],
        schema: OntologySchema.defaults(),
        createdAt: DateTime.utc(2026),
      );
      final String manifest = buildManifest(layer);
      expect(manifest, contains('<ontology-manifest version="ontology_v0">'));
      expect(manifest, contains('可用术语：1 个'));
      expect(manifest, contains('- 收入: 主营收入'));
      expect(manifest, contains('</ontology-manifest>'));
    });
  });
}
