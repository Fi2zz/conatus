/// caching 插件：前缀缓存的度量与装配。
///
/// 服务键 `'contextCache'`（`ctx.contextCache`）。豆包 / DeepSeek 等服务端会按
/// **请求前缀**自动缓存：只要每轮请求的前缀逐字节相同，重复部分就命中缓存。
/// 本插件因此只做三件事：
///
/// * [CachePlan] 求出从头的连续可缓存前缀并给出稳定指纹（纯函数，无副作用）；
/// * [CachingLlmProvider] 原样透传请求，只从响应 `usage` 派生命中情况并产出
///   `context.cache` 遥测——**不往请求体加任何字段**（非标字段可能被 400 拒绝）；
/// * [ContextCache] 作为能力对象持有遥测与命中计数。
library;

import 'dart:convert';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'telemetry.dart';

/// 一次请求的可缓存前缀度量。
class CachePlan {
  const CachePlan._({
    required this.cacheKey,
    required this.cacheableMessages,
    required this.cacheableChars,
    required this.empty,
  });

  /// 求 [messages] 从头的**连续**可缓存前缀：遇到第一条 `cacheable == false`
  /// 即停止，后续即使又出现可缓存消息也不计入。
  ///
  /// 前缀判定依据消息自身内容（`toJson()`），因此尾部增删消息不影响指纹，
  /// 前缀内任何一条消息变化都会改变指纹。
  static CachePlan of(List<LlmMessage> messages) {
    final List<Map<String, dynamic>> prefix = <Map<String, dynamic>>[];
    int chars = 0;
    for (final LlmMessage message in messages) {
      if (!message.cacheable) break;
      prefix.add(message.toJson());
      chars += message.content.length;
    }
    return CachePlan._(
      cacheKey: _fingerprint(prefix),
      cacheableMessages: prefix.length,
      cacheableChars: chars,
      empty: prefix.isEmpty,
    );
  }

  /// 前缀的稳定指纹：内容相同必得同值，前缀变化必然变化。
  final String cacheKey;

  /// 前缀包含的消息条数。
  final int cacheableMessages;

  /// 前缀包含的正文字符数（不含 role 与工具调用）。
  final int cacheableChars;

  /// 前缀是否为空（没有任何可缓存消息）。
  final bool empty;

  static String _fingerprint(List<Map<String, dynamic>> prefix) {
    final List<int> bytes = utf8.encode(jsonEncode(prefix));
    int hash = 0xcbf29ce484222325;
    for (final int byte in bytes) {
      hash = (hash ^ byte) * 0x100000001b3;
    }
    return hash.toRadixString(16);
  }
}

/// 前缀缓存的能力对象：算计划、记命中、发遥测。
class ContextCache {
  /// [telemetry] 为空时不发事件（也不报错）。
  ContextCache({Telemetry? telemetry}) : _telemetry = telemetry;

  final Telemetry? _telemetry;
  int _hits = 0;
  int _misses = 0;

  /// 累计命中次数。
  int get hits => _hits;

  /// 累计未命中次数。
  int get misses => _misses;

  /// 求 [messages] 的可缓存前缀（纯函数，无副作用）。
  CachePlan planFor(List<LlmMessage> messages) => CachePlan.of(messages);

  /// 记录一次调用的缓存结果并产出 `context.cache` 遥测。
  ///
  /// [usage] 是提供方返回的原始用量表；命中与否由它派生，一个命中字段都取不到
  /// 时按未命中计（保守口径）。
  void recordHit({
    required CachePlan plan,
    required Map<String, dynamic> usage,
  }) {
    final bool cached = _cached(usage);
    if (cached) {
      _hits++;
    } else {
      _misses++;
    }
    _telemetry?.emit(TelemetryEvent('context.cache', data: <String, Object?>{
      'cacheKey': plan.cacheKey,
      'cacheableMessages': plan.cacheableMessages,
      'cacheableChars': plan.cacheableChars,
      'hit': cached,
    }));
  }

  bool _cached(Map<String, dynamic> usage) {
    if (_positive(usage['prompt_cache_hit_tokens'])) return true;
    if (_positive(usage['cache_hit_tokens'])) return true;
    final Object? details = usage['prompt_tokens_details'];
    return details is Map && _positive(details['cached_tokens']);
  }

  static bool _positive(Object? value) => value is num && value > 0;
}

/// 缓存度量装饰器：请求与流式调用原样透传，只补一次命中度量。
class CachingLlmProvider implements LlmProvider {
  /// 包装 [inner]，用 [cache] 度量每次调用的前缀缓存情况。
  CachingLlmProvider(this.inner, {required this.cache});

  /// 被包装的提供方。
  final LlmProvider inner;

  /// 缓存能力对象。
  final ContextCache cache;

  @override
  String get name => inner.name;

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    final CachePlan plan = cache.planFor(messages);
    final LlmResult result =
        await inner.chat(messages, options: options, tools: tools);
    cache.recordHit(plan: plan, usage: result.usage);
    return result;
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      inner.chatStream(messages, options: options, tools: tools);

  @override
  void close() => inner.close();
}

/// `ctx.contextCache`：当前上下文可见的前缀缓存能力对象。
extension ContextCacheContext on Context {
  /// 取当前上下文可见的 [ContextCache]（未提供时抛 [StateError]）。
  ContextCache get contextCache => require<ContextCache>('contextCache');
}

/// 把 [ContextCache] 作为 `'contextCache'` 服务提供到上下文。
///
/// [telemetry] 缺省取上下文里已提供的 `'telemetry'`。
ContextCache provideContextCache(
  Context ctx, {
  ContextCache? cache,
  Telemetry? telemetry,
}) {
  final ContextCache resolved = cache ??
      ContextCache(telemetry: telemetry ?? ctx.get<Telemetry>('telemetry'));
  ctx.provide('contextCache', resolved);
  return resolved;
}
