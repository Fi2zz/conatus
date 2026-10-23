import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.reply);

  final String reply;
  final List<LlmMessage> last = <LlmMessage>[];

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    last
      ..clear()
      ..addAll(messages);
    return LlmResult(content: reply, provider: 'scripted', model: 'm');
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

class _ThrowingProvider implements LlmProvider {
  @override
  String get name => 'throwing';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async =>
      throw StateError('boom');

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

class _HangingProvider implements LlmProvider {
  @override
  String get name => 'hanging';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      Completer<LlmResult>().future;

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
  test('从回复里认出档位名并返回对应策略', () async {
    final LlmProfileSelector selector = LlmProfileSelector(
        _ScriptedProvider('{"profile": "compact"}'), kDefaultExecutionProfiles);

    final ExecutionProfile? profile = await selector.select('小任务');

    expect(profile?.name, 'compact');
    expect(profile?.reasoningEffort, 'low');
    expect(profile?.budget.finalizeAfter, 14);
  });

  test('词边界匹配：compacted 不算 compact', () async {
    final LlmProfileSelector selector = LlmProfileSelector(
        _ScriptedProvider('compacted'), kDefaultExecutionProfiles);

    expect(await selector.select('x'), isNull);
  });

  test('未知档位名返回 null', () async {
    final LlmProfileSelector selector = LlmProfileSelector(
        _ScriptedProvider('nonsense'), kDefaultExecutionProfiles);

    expect(await selector.select('x'), isNull);
  });

  test('调用异常与超时都返回 null', () async {
    final LlmProfileSelector broken =
        LlmProfileSelector(_ThrowingProvider(), kDefaultExecutionProfiles);
    final LlmProfileSelector slow = LlmProfileSelector(
        _HangingProvider(), kDefaultExecutionProfiles,
        timeout: const Duration(milliseconds: 10));

    expect(await broken.select('x'), isNull);
    expect(await slow.select('x'), isNull);
  });

  test('任务文本按 maxTaskChars 截断，system 带 rubric', () async {
    final _ScriptedProvider provider = _ScriptedProvider('standard');
    final LlmProfileSelector selector = LlmProfileSelector(
        provider, kDefaultExecutionProfiles,
        maxTaskChars: 8);

    await selector.select('0123456789abcdef');

    expect(provider.last, hasLength(2));
    expect(provider.last.first.role, 'system');
    expect(provider.last.first.content, kExecutionProfileRubric);
    expect(provider.last.last.content.length, 8);
  });

  test('档位表为空时直接返回 null，不调模型', () async {
    final _ScriptedProvider provider = _ScriptedProvider('standard');
    final LlmProfileSelector selector =
        LlmProfileSelector(provider, const <String, ExecutionProfile>{});

    expect(await selector.select('x'), isNull);
    expect(provider.last, isEmpty);
  });

  test('provideProfileSelector 缺 llm 或档位表时不装配', () {
    final Context ctx = Context.root();
    addTearDown(ctx.dispose);

    expect(provideProfileSelector(ctx), isNull);
    expect(ctx.get<ProfileSelector>('profileSelector'), isNull);
  });

  test('provideProfileSelector 从上下文读取 llm 与档位表', () async {
    final Context ctx = Context.root();
    addTearDown(ctx.dispose);
    ctx.provide('llm', _ScriptedProvider('lean'));
    ctx.provide('executionProfiles', kDefaultExecutionProfiles);

    final ProfileSelector? selector = provideProfileSelector(ctx);

    expect(selector, isNotNull);
    expect((await selector!.select('x'))?.name, 'lean');
  });

  test('显式传入的 selector 优先', () async {
    final Context ctx = Context.root();
    addTearDown(ctx.dispose);
    final _FixedSelector fixed = _FixedSelector();

    expect(provideProfileSelector(ctx, selector: fixed), same(fixed));
  });
}

class _FixedSelector implements ProfileSelector {
  @override
  Future<ExecutionProfile?> select(String task) async => null;
}
