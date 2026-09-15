import 'dart:convert';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

const LlmMessage _system = LlmMessage('system', '你是助手', cacheable: true);
const LlmMessage _user = LlmMessage('user', '你好');

class _EchoProvider implements LlmProvider {
  _EchoProvider(this.result);

  final LlmResult result;
  Map<String, dynamic>? lastOptions;
  List<Map<String, dynamic>>? lastTools;

  @override
  String get name => 'echo';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    lastOptions = options;
    lastTools = tools;
    return result;
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

LlmResult _result(Map<String, dynamic> usage) =>
    LlmResult(content: 'ok', provider: 'echo', model: 'm', usage: usage);

void main() {
  group('CachePlan', () {
    test('连续前缀：尾部增删不改变指纹', () {
      final CachePlan base = CachePlan.of(<LlmMessage>[_system, _user]);
      final CachePlan grown = CachePlan.of(<LlmMessage>[
        _system,
        _user,
        const LlmMessage('assistant', '你好呀'),
      ]);

      expect(base.cacheableMessages, 1);
      expect(base.cacheableChars, '你是助手'.length);
      expect(base.empty, isFalse);
      expect(grown.cacheKey, base.cacheKey);
      expect(grown.cacheableMessages, base.cacheableMessages);
    });

    test('前缀变长则指纹变化', () {
      final CachePlan one = CachePlan.of(<LlmMessage>[_system, _user]);
      final CachePlan two = CachePlan.of(<LlmMessage>[
        _system,
        const LlmMessage('user', '你好', cacheable: true)
      ]);

      expect(two.cacheableMessages, 2);
      expect(two.cacheKey, isNot(one.cacheKey));
    });

    test('前缀内内容变化则指纹变化', () {
      final CachePlan one = CachePlan.of(<LlmMessage>[_system, _user]);
      final CachePlan two = CachePlan.of(<LlmMessage>[
        const LlmMessage('system', '你是翻译', cacheable: true),
        _user
      ]);

      expect(two.cacheKey, isNot(one.cacheKey));
    });

    test('前缀非连续：第一条不可缓存即停止', () {
      final CachePlan plan = CachePlan.of(<LlmMessage>[
        _system,
        _user,
        const LlmMessage('assistant', 'x', cacheable: true),
      ]);

      expect(plan.cacheableMessages, 1);
    });

    test('没有可缓存消息时前缀为空', () {
      final CachePlan plan = CachePlan.of(<LlmMessage>[_user]);

      expect(plan.empty, isTrue);
      expect(plan.cacheableMessages, 0);
      expect(plan.cacheableChars, 0);
    });
  });

  test('cacheable 不写入请求体', () {
    expect(_system.toJson().containsKey('cacheable'), isFalse);
    expect(jsonEncode(_system.toJson()), isNot(contains('cacheable')));
  });

  group('CachingLlmProvider', () {
    test('usage 命中时发 context.cache 且 hit 为 true', () async {
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      final ContextCache cache = ContextCache(telemetry: telemetry);
      final _EchoProvider inner = _EchoProvider(
          _result(<String, dynamic>{'prompt_cache_hit_tokens': 128}));
      final Map<String, dynamic> options = <String, dynamic>{
        'temperature': 0.2
      };

      await CachingLlmProvider(inner, cache: cache).chat(
        <LlmMessage>[_system, _user],
        options: options,
        tools: <Map<String, dynamic>>[
          <String, dynamic>{'name': 'get_time'}
        ],
      );

      final TelemetryEvent event = telemetry.recent.single;
      expect(event.name, 'context.cache');
      expect(event.data['hit'], isTrue);
      expect(event.data['cacheableMessages'], 1);
      expect(event.data['cacheableChars'], '你是助手'.length);
      expect(event.data['cacheKey'], isNotEmpty);
      expect(cache.hits, 1);
      expect(cache.misses, 0);
      // 请求原样透传：options 与 tools 都是同一个对象，未加任何字段
      expect(identical(inner.lastOptions, options), isTrue);
      expect(inner.lastTools, hasLength(1));
      await telemetry.close();
    });

    test('usage 为空时 hit 为 false', () async {
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      final ContextCache cache = ContextCache(telemetry: telemetry);

      await CachingLlmProvider(
        _EchoProvider(_result(const <String, dynamic>{})),
        cache: cache,
      ).chat(<LlmMessage>[_system, _user]);

      expect(telemetry.recent.single.data['hit'], isFalse);
      expect(cache.misses, 1);
      await telemetry.close();
    });

    test('嵌套 usage 的 cached_tokens 也算命中', () async {
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      final ContextCache cache = ContextCache(telemetry: telemetry);

      await CachingLlmProvider(
        _EchoProvider(_result(<String, dynamic>{
          'prompt_tokens_details': <String, dynamic>{'cached_tokens': 64},
        })),
        cache: cache,
      ).chat(<LlmMessage>[_system, _user]);

      expect(telemetry.recent.single.data['hit'], isTrue);
      await telemetry.close();
    });

    test('无 telemetry 时只计数不发事件', () async {
      final ContextCache cache = ContextCache();

      await CachingLlmProvider(
        _EchoProvider(_result(<String, dynamic>{'cache_hit_tokens': 8})),
        cache: cache,
      ).chat(<LlmMessage>[_system, _user]);

      expect(cache.hits, 1);
    });

    test('chatStream 原样透传', () async {
      final ContextCache cache = ContextCache();
      final CachingLlmProvider provider = CachingLlmProvider(
        _EchoProvider(_result(const <String, dynamic>{})),
        cache: cache,
      );

      expect(await provider.chatStream(<LlmMessage>[_system, _user]).toList(),
          isEmpty);
      expect(cache.hits, 0);
      expect(provider.name, 'echo');
    });
  });

  group('provideContextCache', () {
    test('作为 contextCache 服务提供', () {
      final Context ctx = Context.root();

      final ContextCache cache = provideContextCache(ctx);

      expect(identical(ctx.contextCache, cache), isTrue);
      ctx.dispose();
    });

    test('复用上下文已提供的 telemetry', () async {
      final Context ctx = Context.root();
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      provideTelemetry(ctx, telemetry: telemetry);
      final ContextCache cache = provideContextCache(ctx);

      cache.recordHit(
        plan: cache.planFor(<LlmMessage>[_system]),
        usage: <String, dynamic>{'cache_hit_tokens': 8},
      );

      expect(telemetry.recent.single.name, 'context.cache');
      expect(telemetry.recent.single.data['hit'], isTrue);
      expect(ctx.contextCache.hits, 1);
      ctx.dispose();
    });

    test('未提供时 ctx.contextCache 抛 StateError', () {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);

      expect(() => ctx.contextCache, throwsStateError);
    });
  });

  group('provideAgentLoop 接入', () {
    test('提供 contextCache 时每次模型调用产出 context.cache', () async {
      final Context ctx = Context.root();
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      provideTelemetry(ctx, telemetry: telemetry);
      provideLlm(ctx,
          llm: FallbackLlm(<LlmProvider>[
            _EchoProvider(
                _result(<String, dynamic>{'prompt_cache_hit_tokens': 128})),
          ]));
      provideTools(ctx);
      provideContextCache(ctx);

      await provideAgentLoop(ctx).run('你好');

      expect(telemetry.recent.map((TelemetryEvent e) => e.name),
          contains('context.cache'));
      expect(
          telemetry.recent
              .firstWhere((TelemetryEvent e) => e.name == 'context.cache')
              .data['hit'],
          isTrue);
      ctx.dispose();
    });

    test('未提供 contextCache 时不包装，行为与从前一致', () async {
      final Context ctx = Context.root();
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      provideTelemetry(ctx, telemetry: telemetry);
      provideLlm(ctx,
          llm: FallbackLlm(<LlmProvider>[
            _EchoProvider(_result(const <String, dynamic>{})),
          ]));
      provideTools(ctx);

      final AgentTurn turn = await provideAgentLoop(ctx).run('你好');

      expect(turn.reply, 'ok');
      expect(telemetry.recent.map((TelemetryEvent e) => e.name),
          isNot(contains('context.cache')));
      ctx.dispose();
    });
  });
}
