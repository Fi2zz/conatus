import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_ontology/src/evolver/evaluator.dart';
import 'package:conatus_ontology/src/evolver/evolver.dart';
import 'package:conatus_ontology/src/evolver/paired_evaluator.dart';
import 'package:conatus_ontology/src/ontology/edits.dart';
import 'package:conatus_ontology/src/ontology/layer.dart';
import 'package:conatus_ontology/src/ontology/node.dart';
import 'package:conatus_ontology/src/ontology/relation.dart';
import 'package:conatus_ontology/src/ontology/schema.dart';
import 'package:test/test.dart';

OntologyLayer _layer(String version) => OntologyLayer(
      version: version,
      nodes: <OntologyNode>[
        Term(id: 't1', createdAt: DateTime.utc(2026), name: '收入', definition: 'd'),
      ],
      relations: const <SemanticRelation>[],
      references: const <StructuralReference>[],
      schema: OntologySchema.defaults(),
      createdAt: DateTime.utc(2026),
    );

List<EvalCase> _cases(int n) =>
    List<EvalCase>.generate(n, (int i) => EvalCase(id: 'c$i', input: 'q$i'));

void main() {
  const BackboneConfig backbone =
      BackboneConfig(provider: 'volc', model: 'doubao-pro');

  group('PairedEvaluator.evaluate', () {
    test('改进达到阈值时通过', () async {
      String currentVersion = '';
      final PairedEvaluator evaluator = PairedEvaluator(
        backbones: const <BackboneConfig>[backbone],
        resolver: (BackboneConfig b) => Evaluator(
          run: (String input) async => const AgentTurn(
              reply: 'ok', messages: <LlmMessage>[], steps: <AgentStep>[]),
          judge: (EvalCase evalCase, EvalResult result) {
            // parent 全挂，candidate 全过 → 改进 1.0。
            return currentVersion == 'v1';
          },
        ),
      );

      final ConditionalEvalResult result = await evaluator.evaluate(
        parent: _layer('v0'),
        candidate: _layer('v1'),
        cases: _cases(4),
        apply: (OntologyLayer layer) async {
          currentVersion = layer.version;
        },
      );
      expect(result.passed, isTrue);
      expect(result.baselineScore, 0);
      expect(result.candidateScore, 1);
      expect(result.improvement, 1);
      expect(result.backbone.provider, 'volc');
    });

    test('无 backbone 达到阈值时拒绝', () async {
      final PairedEvaluator evaluator = PairedEvaluator(
        backbones: const <BackboneConfig>[backbone],
        resolver: (BackboneConfig b) => Evaluator(
          run: (String input) async => const AgentTurn(
              reply: 'ok', messages: <LlmMessage>[], steps: <AgentStep>[]),
          judge: (EvalCase evalCase, EvalResult result) => true,
        ),
      );
      final ConditionalEvalResult result = await evaluator.evaluate(
        parent: _layer('v0'),
        candidate: _layer('v1'),
        cases: _cases(2),
        apply: (OntologyLayer layer) async {},
      );
      expect(result.passed, isFalse);
      expect(result.improvement, 0);
    });

    test('第一个 backbone 通过后不再评估后续 backbone', () async {
      String currentVersion = '';
      final List<String> evaluatedBackbones = <String>[];
      final PairedEvaluator evaluator = PairedEvaluator(
        backbones: const <BackboneConfig>[
          backbone,
          BackboneConfig(provider: 'deepseek', model: 'v3'),
        ],
        resolver: (BackboneConfig b) {
          evaluatedBackbones.add(b.label);
          return Evaluator(
            run: (String input) async => const AgentTurn(
                reply: 'ok', messages: <LlmMessage>[], steps: <AgentStep>[]),
            judge: (EvalCase evalCase, EvalResult result) =>
                currentVersion == 'v1',
          );
        },
      );
      final ConditionalEvalResult result = await evaluator.evaluate(
        parent: _layer('v0'),
        candidate: _layer('v1'),
        cases: _cases(1),
        apply: (OntologyLayer layer) async {
          currentVersion = layer.version;
        },
      );
      expect(result.passed, isTrue);
      expect(evaluatedBackbones, hasLength(1));
    });

    test('apply 依次收到 parent 与 candidate', () async {
      final List<String> applied = <String>[];
      final PairedEvaluator evaluator = PairedEvaluator(
        backbones: const <BackboneConfig>[backbone],
        resolver: (BackboneConfig b) => Evaluator(
          run: (String input) async => const AgentTurn(
              reply: 'ok', messages: <LlmMessage>[], steps: <AgentStep>[]),
        ),
      );
      await evaluator.evaluate(
        parent: _layer('v0'),
        candidate: _layer('v1'),
        cases: _cases(1),
        apply: (OntologyLayer layer) async {
          applied.add(layer.version);
        },
      );
      expect(applied, <String>['v0', 'v1']);
    });
  });

  group('BackboneConfig', () {
    test('label 拼接 provider/model', () {
      expect(backbone.label, 'volc/doubao-pro');
    });
  });

  group('OntologyVariant JSON', () {
    test('往返', () {
      final variant = OntologyVariant(
        id: 'v1',
        parentVersion: 'v0',
        edits: const <TypedEdit>[],
        createdAt: DateTime.utc(2026),
        reason: 'r',
      );
      final restored = OntologyVariant.fromJson(variant.toJson());
      expect(restored.id, 'v1');
      expect(restored.parentVersion, 'v0');
      expect(restored.edits, isEmpty);
      expect(restored.reason, 'r');
    });
  });
}
