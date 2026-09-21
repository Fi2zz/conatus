import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_ontology/conatus_ontology.dart';
import 'package:test/test.dart';

class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.replies);

  final List<String> replies;
  int _index = 0;

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
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

void main() {
  group('provideOntology 装配', () {
    test('显式传入 llm 时可用 browse/build', () async {
      final Context ctx = Context.root();
      final OntologyService service = provideOntology(
        ctx,
        llm: _ScriptedProvider(const <String>[
          '[{"name": "营业收入", "definition": "d", "aliases": ["amount"]}]',
        ]),
      );
      expect(ctx.ontology, same(service));
      await service.build(sources: const <DataSource>[
        DataSource(
          id: 'sales',
          name: '销售订单',
          columns: <DataColumn>[DataColumn(name: 'amount', type: 'number')],
          sampleRows: <Map<String, Object?>>[
            <String, Object?>{'amount': 1},
          ],
        ),
      ]);
      expect((await service.browse(type: 'term')), hasLength(1));
      ctx.dispose();
    });

    test('缺省从上下文取 llm，缺失抛 StateError', () {
      final Context ctx = Context.root();
      expect(
        () => provideOntology(ctx),
        throwsStateError,
      );
      ctx.dispose();
    });

    test('已注册服务时复用', () {
      final Context ctx = Context.root();
      final OntologyService first = provideOntology(
        ctx,
        llm: _ScriptedProvider(const <String>[]),
      );
      final OntologyService second = provideOntology(
        ctx,
        llm: _ScriptedProvider(const <String>[]),
      );
      expect(second, same(first));
      ctx.dispose();
    });
  });

  group('主入口导出', () {
    test('核心类型与函数可从包入口使用', () {
      final Term term = Term(
          id: 't2', createdAt: DateTime.utc(2026), name: 'y', definition: 'e');
      expect(term.type, 'term');
      expect(provideOntology, isA<Function>());
      expect(buildManifest, isA<Function>());
      expect(applyEdits, isA<Function>());
      expect(groundTerm, isA<Function>());
      expect(evolveVariant, isA<Function>());
    });
  });
}
