import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

/// 记录每次 chat 请求的脚本化提供方；与 `agent_loop_test.dart` 的
/// `_ScriptedProvider` 同构，但固定返回 `'你好'` 且只留证据断言所需字段。
class _Provider implements LlmProvider {
  final List<List<LlmMessage>> calls = <List<LlmMessage>>[];

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls.add(List<LlmMessage>.of(messages));
    return const LlmResult(content: '你好', provider: 'scripted', model: 'm');
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
  group('EvidenceSource 钩子', () {
    test('未接线：请求只有一条 system', () async {
      final _Provider provider = _Provider();
      final AgentLoop loop = AgentLoop(llm: provider, tools: ToolRegistry());

      await loop.run('在吗');

      final List<LlmMessage> systems = provider.calls.first
          .where((LlmMessage m) => m.role == 'system')
          .toList();
      expect(systems, hasLength(1));
    });

    test('接线：第二条 system 注入证据且 cacheable=false，首条 cacheable=true', () async {
      final _Provider provider = _Provider();
      final AgentLoop loop = AgentLoop(
        llm: provider,
        tools: ToolRegistry(),
        evidence: (String input) async => '[相关历史证据]\n- 事实 A',
      );

      await loop.run('在吗');

      final List<LlmMessage> systems = provider.calls.last
          .where((LlmMessage m) => m.role == 'system')
          .toList();
      expect(systems, hasLength(2));
      expect(systems.last.content, contains('事实 A'));
      expect(systems.last.cacheable, isFalse);
      expect(systems.first.cacheable, isTrue);
    });

    test('钩子抛错：不注入且本轮照常收口', () async {
      final _Provider provider = _Provider();
      final AgentLoop loop = AgentLoop(
        llm: provider,
        tools: ToolRegistry(),
        evidence: (String input) async => throw StateError('端点挂了'),
      );

      final AgentTurn turn = await loop.run('在吗');

      expect(turn.reply, '你好');
      final List<LlmMessage> systems = provider.calls.last
          .where((LlmMessage m) => m.role == 'system')
          .toList();
      expect(systems, hasLength(1));
    });

    test('钩子返回空串/空白：不注入', () async {
      final _Provider provider = _Provider();
      final AgentLoop loop = AgentLoop(
        llm: provider,
        tools: ToolRegistry(),
        evidence: (String input) async => '   \n  ',
      );

      await loop.run('在吗');

      final List<LlmMessage> systems = provider.calls.last
          .where((LlmMessage m) => m.role == 'system')
          .toList();
      expect(systems, hasLength(1));
    });
  });
}
