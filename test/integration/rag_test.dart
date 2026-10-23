import 'dart:io';

import 'package:conatus/conatus.dart';
import 'package:test/test.dart';

import 'helpers/scripted_llm.dart';

/// 所有文本映射到同一向量的嵌入器：足以验证租户隔离与注入链路，无需真实端点。
class _ConstantEmbedder implements Embedder {
  @override
  String get model => 'fixture';

  @override
  int get dimension => 2;

  @override
  Future<List<double>> embed(String text) async => <double>[1, 0];

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async =>
      <List<double>>[
        for (final String _ in texts) <double>[1, 0],
      ];

  @override
  void dispose() {}
}

void main() {
  test('租户 A 的事实可注入/可检索，租户 B 一律取不到；forget 后消失', () async {
    final Directory dir = await Directory.systemTemp.createTemp('rag-it');
    addTearDown(() => dir.deleteSync(recursive: true));
    final SessionLog log = PersistenceSessionLog(
      JsonlSessionPersistence(dir: dir.path),
    );
    await log.append(
      SessionEvent.create(
        sessionId: 'a-s1',
        seq: 0,
        type: kUserMessageEvent,
        data: <String, Object?>{'text': '我的工号是 E-778'},
      ),
    );

    final Context app = Context.root();
    addTearDown(app.dispose);
    provideTools(app);
    provideSystemPrompt(app);
    provideSessionLog(app, log: log);
    final RagService rag = provideRag(
      app,
      config: RagConfig(embedder: _ConstantEmbedder()),
      scopeOf: (String id) async =>
          RagScope(tenantId: id.startsWith('a-') ? 'ta' : 'tb'),
    );

    final RagScope ta = RagScope(tenantId: 'ta');
    final RagScope tb = RagScope(tenantId: 'tb');
    await rag.ingestSession('a-s1');
    expect(
      await rag.retrieve(RetrievalRequest(query: '工号', scope: ta)),
      isNotEmpty,
    );
    expect(
      await rag.retrieve(RetrievalRequest(query: '工号', scope: tb)),
      isEmpty,
    );

    final RagSearchTool asB = RagSearchTool(service: rag, scope: tb);
    final ToolResult denied = await asB.call(
      const ToolContext(
        ToolCall(
          name: 'rag_search',
          arguments: <String, Object?>{'query': '工号'},
        ),
      ),
    );
    expect((denied.value! as Map<String, Object?>)['count'], 0);

    final ScriptedLlm llmB = ScriptedLlm(<LlmResult>[text('好的')]);
    final AgentLoop loopB = AgentLoop(
      llm: llmB,
      tools: ToolRegistry(),
      evidence: (String q) => rag.evidenceBlock(q, tb),
    );
    await loopB.run('我的工号是多少');
    expect(
      llmB.requests.single.any((LlmMessage m) => m.content.contains('E-778')),
      isFalse,
    );

    final ScriptedLlm llmA = ScriptedLlm(<LlmResult>[text('好的')]);
    final AgentLoop loopA = AgentLoop(
      llm: llmA,
      tools: ToolRegistry(),
      evidence: (String q) => rag.evidenceBlock(q, ta),
    );
    await loopA.run('我的工号是多少');
    expect(
      llmA.requests.single.any(
        (LlmMessage m) => m.role == 'system' && m.content.contains('E-778'),
      ),
      isTrue,
    );

    await rag.forgetSession('a-s1', scope: ta);
    expect(
      await rag.retrieve(RetrievalRequest(query: '工号', scope: ta)),
      isEmpty,
    );
  });
}
