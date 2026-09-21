import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_ontology/src/benchmark/adapter.dart';
import 'package:conatus_ontology/src/benchmark/bird.dart';
import 'package:conatus_ontology/src/builder/source.dart';
import 'package:conatus_ontology/src/evolver/evaluator.dart';
import 'package:conatus_ontology/src/ontology/layer.dart';
import 'package:conatus_ontology/src/ontology/node.dart';
import 'package:conatus_ontology/src/ontology/relation.dart';
import 'package:conatus_ontology/src/ontology/schema.dart';
import 'package:test/test.dart';

class _FakeAdapter implements EvolutionAdapter {
  @override
  String get name => 'fake';

  @override
  Future<List<DataSource>> loadSources() async => const <DataSource>[];

  @override
  Future<List<EvalCase>> loadCases() async => const <EvalCase>[];

  @override
  Future<RolloutResult> rollout({
    required OntologyLayer ontology,
    required BackboneConfig backbone,
    required EvalCase testCase,
  }) async => RolloutResult(
        turn: const AgentTurn(
            reply: 'SELECT 1',
            messages: <LlmMessage>[],
            steps: <AgentStep>[]),
        expected: testCase.expectedOutput ?? '',
      );

  @override
  double evaluate(RolloutResult result, EvalCase testCase) =>
      result.turn.reply == 'SELECT 1' ? 1.0 : 0.0;
}

OntologyLayer _layer() => OntologyLayer(
      version: 'ontology_v0',
      nodes: const <OntologyNode>[],
      relations: const <SemanticRelation>[],
      references: const <StructuralReference>[],
      schema: OntologySchema.defaults(),
      createdAt: DateTime.utc(2026),
    );

void main() {
  group('EvolutionAdapter 契约', () {
    test('rollout 与 evaluate 可用', () async {
      final _FakeAdapter adapter = _FakeAdapter();
      const EvalCase evalCase = EvalCase(id: 'c1', input: 'q', expectedOutput: 'SELECT 1');
      final RolloutResult result = await adapter.rollout(
        ontology: _layer(),
        backbone: const BackboneConfig(provider: 'p', model: 'm'),
        testCase: evalCase,
      );
      expect(adapter.name, 'fake');
      expect(adapter.evaluate(result, evalCase), 1.0);
    });
  });

  group('BirdAdapter', () {
    test('名字与骨架', () {
      const BirdAdapter adapter = BirdAdapter();
      expect(adapter.name, 'bird');
      expect(adapter.loadSources(), completes);
      expect(adapter.loadCases(), completes);
    });

    test('Execution Accuracy：结果一致得 1 分，否则 0 分', () {
      const BirdAdapter adapter = BirdAdapter();
      const EvalCase evalCase = EvalCase(id: 'c1', input: 'q', expectedOutput: '1');
      const RolloutResult hit = RolloutResult(
        turn: AgentTurn(
            reply: '1', messages: <LlmMessage>[], steps: <AgentStep>[]),
        expected: '1',
      );
      const RolloutResult miss = RolloutResult(
        turn: AgentTurn(
            reply: '2', messages: <LlmMessage>[], steps: <AgentStep>[]),
        expected: '1',
      );
      expect(adapter.evaluate(hit, evalCase), 1.0);
      expect(adapter.evaluate(miss, evalCase), 0.0);
    });
  });
}
