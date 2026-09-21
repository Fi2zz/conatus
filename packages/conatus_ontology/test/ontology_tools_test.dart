import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart' hide MemoryStore;
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_ontology/src/builder/source.dart';
import 'package:conatus_ontology/src/evolver/evaluator.dart';
import 'package:conatus_ontology/src/evolver/paired_evaluator.dart';
import 'package:conatus_ontology/src/mcp/tools.dart';
import 'package:conatus_ontology/src/runtime/service_default.dart';
import 'package:conatus_ontology/src/store/memory_store.dart' as ontology;
import 'package:conatus_ontology/src/tools/ontology_tools.dart';
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
    columns: <DataColumn>[DataColumn(name: 'amount', type: 'number')],
    sampleRows: <Map<String, Object?>>[
      <String, Object?>{'amount': 100},
    ],
  ),
];

/// 通过 build 构造带「营业收入」术语的服务（Mock LLM 返回提取结果）。
Future<DefaultOntologyService> _service() async {
  final DefaultOntologyService service = DefaultOntologyService(
    llm: _ScriptedProvider(const <String>[
      '[{"name": "营业收入", "definition": "主营收入", "aliases": ["amount"]}]',
    ]),
    store: ontology.MemoryStore(),
    pairedEvaluator: PairedEvaluator(
      backbones: const <BackboneConfig>[],
      resolver: (BackboneConfig b) => Evaluator(
          run: (String input) async => const AgentTurn(
              reply: 'ok', messages: <LlmMessage>[], steps: <AgentStep>[])),
    ),
    evalCases: const <EvalCase>[],
  );
  await service.build(sources: _sources);
  return service;
}

DefaultOntologyService _stubService() => DefaultOntologyService(
      llm: _ScriptedProvider(const <String>['[]']),
      store: ontology.MemoryStore(),
      pairedEvaluator: PairedEvaluator(
        backbones: const <BackboneConfig>[],
        resolver: (BackboneConfig b) => Evaluator(
            run: (String input) async => const AgentTurn(
                reply: 'ok', messages: <LlmMessage>[], steps: <AgentStep>[])),
      ),
      evalCases: const <EvalCase>[],
    );

void main() {
  group('browse_semantics', () {
    test('type 过滤返回摘要 JSON', () async {
      final DefaultOntologyService service = await _service();
      final BrowseSemanticsTool tool = BrowseSemanticsTool(ontology: service);
      final ToolResult result = await tool.call(const ToolContext(
          ToolCall(name: 'browse_semantics', arguments: <String, Object?>{
        'type': 'term',
      })));
      expect(result.isError, isFalse);
      expect(result.content, contains('营业收入'));
    });

    test('query 无命中返回空数组', () async {
      final DefaultOntologyService service = await _service();
      final BrowseSemanticsTool tool = BrowseSemanticsTool(ontology: service);
      final ToolResult result = await tool.call(const ToolContext(
          ToolCall(name: 'browse_semantics', arguments: <String, Object?>{
        'query': '不存在的词',
      })));
      expect(result.content, '[]');
    });
  });

  group('resolve_semantics', () {
    test('解析存在的术语返回完整记录', () async {
      final DefaultOntologyService service = await _service();
      final ResolveSemanticsTool tool = ResolveSemanticsTool(ontology: service);
      final ToolResult result = await tool.call(const ToolContext(
          ToolCall(name: 'resolve_semantics', arguments: <String, Object?>{
        'term': '营业收入',
      })));
      expect(result.isError, isFalse);
      expect(result.content, contains('sales.amount'));
    });

    test('缺失术语返回失败', () async {
      final DefaultOntologyService service = await _service();
      final ResolveSemanticsTool tool = ResolveSemanticsTool(ontology: service);
      final ToolResult result = await tool.call(const ToolContext(
          ToolCall(name: 'resolve_semantics', arguments: <String, Object?>{
        'term': '不存在',
      })));
      expect(result.isError, isTrue);
      expect(result.error!.code, 'TERM_NOT_FOUND');
    });
  });

  group('ontology_manifest', () {
    test('输出紧凑清单', () async {
      final DefaultOntologyService service = await _service();
      final OntologyManifestTool tool = OntologyManifestTool(ontology: service);
      final ToolResult result = await tool.call(
          const ToolContext(ToolCall(name: 'ontology_manifest')));
      expect(result.isError, isFalse);
      expect(result.content, contains('<ontology-manifest'));
      expect(result.content, contains('营业收入'));
    });

    test('未构建时返回失败', () async {
      final OntologyManifestTool tool =
          OntologyManifestTool(ontology: _stubService());
      final ToolResult result = await tool.call(
          const ToolContext(ToolCall(name: 'ontology_manifest')));
      expect(result.isError, isTrue);
    });
  });

  group('registerOntologyTools', () {
    test('注册三个工具且可注销', () {
      final Context ctx = Context.root();
      ctx.provide('tools', ToolRegistry());
      final Disposer disposer =
          registerOntologyTools(ctx, ontology: _stubService());
      expect(ctx.tools.describeOne('browse_semantics'), isNotNull);
      expect(ctx.tools.describeOne('resolve_semantics'), isNotNull);
      expect(ctx.tools.describeOne('ontology_manifest'), isNotNull);

      disposer();
      expect(ctx.tools.describeOne('browse_semantics'), isNull);
      ctx.dispose();
    });
  });
}
