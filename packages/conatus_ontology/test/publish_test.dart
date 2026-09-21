import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_ontology/src/builder/source.dart';
import 'package:conatus_ontology/src/evolver/evaluator.dart';
import 'package:conatus_ontology/src/evolver/evolver.dart';
import 'package:conatus_ontology/src/evolver/paired_evaluator.dart';
import 'package:conatus_ontology/src/ontology/edits.dart';
import 'package:conatus_ontology/src/ontology/node.dart';
import 'package:conatus_ontology/src/runtime/service.dart';
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

const BackboneConfig _backbone =
    BackboneConfig(provider: 'volc', model: 'doubao-pro');

OntologyVariant _variant() {
  return OntologyVariant(
    id: 'candidate-1',
    parentVersion: 'ontology_v0',
    edits: <TypedEdit>[
      AddNode(Term(
          id: 't2',
          createdAt: DateTime.utc(2026),
          name: 'x',
          definition: 'd')),
    ],
    createdAt: DateTime.utc(2026),
  );
}

/// candidate 层比 parent 多一个 term，使配对评估可区分。
Future<DefaultOntologyService> _service({
  required _ScriptedProvider llm,
  bool candidatePasses = true,
  Approval? approval,
  InMemoryTelemetry? telemetry,
}) async {
  final List<EvalCase> evalCases = <EvalCase>[
    const EvalCase(id: 'c1', input: '查询收入'),
  ];
  int judgeCalls = 0;
  final DefaultOntologyService service = DefaultOntologyService(
    llm: llm,
    store: MemoryStore(),
    pairedEvaluator: PairedEvaluator(
      backbones: const <BackboneConfig>[_backbone],
      resolver: (BackboneConfig b) => Evaluator(
        run: (String input) async =>
            const AgentTurn(reply: 'ok', messages: <LlmMessage>[], steps: <AgentStep>[]),
        judge: (EvalCase evalCase, EvalResult result) {
          final bool isCandidateRound = judgeCalls++ >= evalCases.length;
          return isCandidateRound && candidatePasses;
        },
      ),
    ),
    evalCases: evalCases,
    approval: approval,
    telemetry: telemetry,
  );
  await service.build(sources: const <DataSource>[]);
  return service;
}

void main() {
  group('publish', () {
    test('改进不足时拒绝并发出事件', () async {
      final DefaultOntologyService service = await _service(
          llm: _ScriptedProvider(const <String>['[]']), candidatePasses: false);
      final List<OntologyEvent> events = <OntologyEvent>[];
      service.changes.listen(events.add);

      final bool published = await service.publish(_variant());
      expect(published, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(events.single, isA<OntologyRejected>());
      expect(service.current!.version, 'ontology_v0');
    });

    test('通过评估但用户拒绝时拒绝', () async {
      final DefaultOntologyService service = await _service(
        llm: _ScriptedProvider(const <String>['[]']),
        approval: AutoApproval(false),
      );
      final bool published = await service.publish(_variant());
      expect(published, isFalse);
      expect(service.current!.version, 'ontology_v0');
    });

    test('通过评估与确认后发布新版本', () async {
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      final DefaultOntologyService service = await _service(
        llm: _ScriptedProvider(const <String>['[]']),
        approval: AutoApproval(true),
        telemetry: telemetry,
      );
      final List<OntologyEvent> events = <OntologyEvent>[];
      service.changes.listen(events.add);

      final bool published = await service.publish(_variant());
      expect(published, isTrue);
      expect(service.current!.version, 'ontology_v1');
      expect(service.current!.parentVersion, 'ontology_v0');
      expect(service.versions, hasLength(2));
      await Future<void>.delayed(Duration.zero);
      expect(events.single, isA<OntologyPublished>());
      expect(
        telemetry.recent.any((TelemetryEvent e) => e.name == 'ontology.published'),
        isTrue,
      );
    });

    test('发布后可回滚', () async {
      final DefaultOntologyService service = await _service(
        llm: _ScriptedProvider(const <String>['[]']),
        approval: AutoApproval(true),
      );
      await service.publish(_variant());
      expect(service.current!.version, 'ontology_v1');

      await service.rollback('ontology_v0');
      expect(service.current!.version, 'ontology_v0');
      await expectLater(service.rollback('nope'), throwsStateError);
    });
  });
}
