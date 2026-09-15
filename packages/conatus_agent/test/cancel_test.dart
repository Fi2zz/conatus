import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

/// 模型调用挂起不返回，直到被取消（模拟对端不响应）。
class _HangingProvider implements LlmProvider {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  String get name => 'hanging';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    return const LlmResult(content: '迟到的回复', provider: 'hanging', model: 'm');
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
  }) => const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

void main() {
  test('取消在飞模型调用：run 立刻以 AgentCancelled 结束', () async {
    final _HangingProvider provider = _HangingProvider();
    final AgentLoop loop = AgentLoop(llm: provider, tools: ToolRegistry());
    final AgentCancel cancel = AgentCancel();

    final Future<AgentTurn> running = loop.run('你好', cancel: cancel);
    await provider.started.future;
    cancel.cancel();

    await expectLater(running, throwsA(isA<AgentCancelled>()));
    provider.release.complete(); // 迟到结果被丢弃，不应抛未处理错误。
  });

  test('已取消的信号：run 立即结束', () async {
    final _HangingProvider provider = _HangingProvider();
    final AgentLoop loop = AgentLoop(llm: provider, tools: ToolRegistry());
    final AgentCancel cancel = AgentCancel()..cancel();

    await expectLater(
      loop.run('你好', cancel: cancel),
      throwsA(isA<AgentCancelled>()),
    );
  });

  test('不传 cancel：行为与无取消一致', () async {
    final _HangingProvider provider = _HangingProvider();
    final AgentLoop loop = AgentLoop(llm: provider, tools: ToolRegistry());

    final Future<AgentTurn> running = loop.run('你好');
    await provider.started.future;
    provider.release.complete();

    expect((await running).reply, '迟到的回复');
  });
}
