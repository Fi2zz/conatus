/// 轮次记录器：把策略接到 Agent Loop 的生命周期上，并保持 fail-open。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_memory/conatus_memory.dart';
import 'package:test/test.dart';

/// 保存即失败的存储，用于验证 fail-open。
class _BrokenBackend implements MemoryBackend {
  @override
  Future<List<MemoryEntry>> load() async => const <MemoryEntry>[];

  @override
  Future<void> save(List<MemoryEntry> entries) async =>
      throw StateError('磁盘坏了');
}

MemoryRecorder _recorder(
  MemoryStore memory, {
  MemoryWritePolicy policy = const PolicyMemoryWritePolicy(),
  void Function(MemoryWriteDecision)? onStore,
}) =>
    MemoryRecorder(memory: memory, policy: policy, onStore: onStore);

void main() {
  test('正常轮次写入一条，正文来自策略', () async {
    final MemoryStore memory = MemoryStore();
    final MemoryRecorder recorder = _recorder(memory);

    await recorder.beginTurn('项目用 Dart 还是 Kotlin？');
    await recorder.endTurn(result: '这个项目使用 Dart 语言。');

    expect(memory.length, 1);
    expect(memory.entries.single.text, contains('用户：项目用 Dart 还是 Kotlin？'));
    expect(memory.entries.single.tags, contains('conversation'));
  });

  test('失败轮次不写', () async {
    final MemoryStore memory = MemoryStore();
    final MemoryRecorder recorder = _recorder(memory);

    await recorder.beginTurn('项目用 Dart 还是 Kotlin？');
    await recorder.endTurn(error: StateError('模型挂了'));

    expect(memory.length, 0);
  });

  test('短回复不写', () async {
    final MemoryStore memory = MemoryStore();
    final MemoryRecorder recorder = _recorder(memory);

    await recorder.beginTurn('帮我看看这个配置');
    await recorder.endTurn(result: '好的');

    expect(memory.length, 0);
  });

  test('写入失败不外抛（fail-open）', () async {
    final MemoryStore memory = MemoryStore(backend: _BrokenBackend());
    final MemoryRecorder recorder = _recorder(memory);

    await recorder.beginTurn('帮我记住项目用 Dart');
    await recorder.endTurn(result: '已记录：项目语言是 Dart。');

    expect(memory.length, 1, reason: '内存里已追加，只是落盘失败');
  });

  test('连续两轮相同内容只写一条', () async {
    final MemoryStore memory = MemoryStore();
    final MemoryRecorder recorder = _recorder(memory);

    for (int i = 0; i < 2; i++) {
      await recorder.beginTurn('项目用 Dart 还是 Kotlin？');
      await recorder.endTurn(result: '这个项目使用 Dart 语言。');
    }

    expect(memory.length, 1);
  });

  test('onStore 收到决策（含判定原因）', () async {
    final MemoryStore memory = MemoryStore();
    final List<MemoryWriteVerdict> verdicts = <MemoryWriteVerdict>[];
    final MemoryRecorder recorder = _recorder(memory,
        onStore: (MemoryWriteDecision d) => verdicts.add(d.verdict));

    await recorder.beginTurn('你好');
    await recorder.endTurn(result: '你好，有什么可以帮你？');

    expect(verdicts.single, MemoryWriteVerdict.greeting);
  });

  test('未开始轮次时 endTurn 不写', () async {
    final MemoryStore memory = MemoryStore();
    final MemoryRecorder recorder = _recorder(memory);

    await recorder.endTurn(result: '这个项目使用 Dart 语言。');

    expect(memory.length, 0);
  });

  test('provideMemoryRecorder 挂到 agentLoop，dispose 后摘除', () async {
    final Context ctx = Context.root();
    final AgentLoop loop = AgentLoop(
      llm: _UnusedProvider(),
      tools: ToolRegistry(),
    );
    ctx.provide('agentLoop', loop);
    ctx.provide('memory', MemoryStore());

    final MemoryRecorder recorder = provideMemoryRecorder(ctx);
    expect(loop.turnTrackers, contains(recorder));

    ctx.dispose();
    expect(loop.turnTrackers, isEmpty);
  });

  test('端到端：装配后一轮对话落进记忆', () async {
    final Context ctx = Context.root();
    final MemoryStore memory = MemoryStore();
    final AgentLoop loop = AgentLoop(
      llm: _ScriptedProvider('这个项目使用 Dart 语言，构建工具是 pub。'),
      tools: ToolRegistry(),
    );
    ctx.provide('agentLoop', loop);
    ctx.provide('memory', memory);
    provideMemoryRecorder(ctx);

    await loop.run('这个项目用什么语言？');

    expect(memory.length, 1);
    expect(memory.entries.single.text, contains('这个项目用什么语言？'));

    ctx.dispose();
  });
}

class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.reply);

  final String reply;

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async =>
      LlmResult(content: reply, provider: 'scripted', model: 'm');

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

class _UnusedProvider implements LlmProvider {
  @override
  String get name => 'unused';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async =>
      const LlmResult(content: '', provider: 'unused', model: 'm');

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
