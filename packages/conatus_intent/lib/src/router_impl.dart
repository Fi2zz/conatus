/// 默认意图路由器：先正则、后向量，都未命中返回 missed。
library;

import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'embedding/embedding_provider.dart';
import 'errors.dart';
import 'events.dart';
import 'intent.dart';
import 'matcher/regex_matcher.dart';
import 'matcher/vector_matcher.dart';
import 'route.dart';
import 'router.dart';

/// 按需解析当前会话；返回 null 表示不记录 `intent/routed` 事件。
///
/// 装配路由器时通常还没有会话（会话往往在 Agent Loop 绑定时才确定），因此用解析
/// 函数而不是直接传 `Session`。
typedef SessionLookup = Session? Function();

/// [IntentRouter] 的默认实现。
///
/// 未配 [embedder] 时只跑正则；配了但嵌入生成失败时，该意图被跳过（不阻塞路由）。
class DefaultIntentRouter implements IntentRouter {
  /// 构造路由器。
  DefaultIntentRouter({
    EmbeddingProvider? embedder,
    this.vectorThreshold = 0.85,
    this.telemetry,
    this.sessionOf,
  }) : _embedder = embedder;

  /// 向量命中阈值。
  final double vectorThreshold;

  /// 埋点端口；null 表示不埋点。
  final Telemetry? telemetry;

  /// 会话解析者；null 表示不记录 `intent/routed` 事件。
  final SessionLookup? sessionOf;

  final EmbeddingProvider? _embedder;
  final Map<String, Intent> _intents = <String, Intent>{};
  final Map<String, Future<List<double>?>> _embeddings =
      <String, Future<List<double>?>>{};
  final StreamController<IntentEvent> _changes =
      StreamController<IntentEvent>.broadcast();
  static const RegexMatcher _regex = RegexMatcher();

  late final VectorMatcher? _vector = _buildVectorMatcher();

  @override
  List<Intent> get intents => List<Intent>.unmodifiable(_intents.values);

  @override
  Stream<IntentEvent> get changes => _changes.stream;

  @override
  void register(Intent intent) {
    if (_intents.containsKey(intent.name)) {
      throw IntentException('duplicate', '意图已注册: ${intent.name}');
    }
    _intents[intent.name] = intent;
    _changes.add(IntentRegistered(intent));
    _emit('intent.registered', <String, Object?>{'name': intent.name});
    _startEmbedding(intent);
  }

  @override
  void unregister(String name) {
    if (_intents.remove(name) == null) return;
    _embeddings.remove(name);
    _changes.add(IntentUnregistered(name));
    _emit('intent.unregistered', <String, Object?>{'name': name});
  }

  @override
  Future<RouteResult> route(String input, {Map<String, Object?>? state}) async {
    final String trimmed = input.trim();
    if (trimmed.isEmpty) return RouteResult.missed(input);
    final RouteResult? hit =
        _regex.match(trimmed, intents) ?? await _matchVector(trimmed);
    if (hit == null) return _miss(input, trimmed);
    return _record(hit);
  }

  @override
  void dispose() {
    _changes.close();
    _embedder?.dispose();
  }

  VectorMatcher? _buildVectorMatcher() {
    final EmbeddingProvider? embedder = _embedder;
    if (embedder == null) return null;
    return VectorMatcher(
      embedder: embedder,
      embeddingOf: _embeddingOf,
      threshold: vectorThreshold,
    );
  }

  Future<RouteResult?> _matchVector(String input) async {
    final VectorMatcher? matcher = _vector;
    if (matcher == null) return null;
    try {
      return await matcher.match(input, intents);
    } catch (error) {
      _emit('intent.vector.failed', <String, Object?>{'error': '$error'});
      return null;
    }
  }

  Future<List<double>?> _embeddingOf(Intent intent) {
    final List<double>? precomputed = intent.embedding;
    if (precomputed != null) return Future<List<double>?>.value(precomputed);
    return _embeddings[intent.name] ?? Future<List<double>?>.value();
  }

  void _startEmbedding(Intent intent) {
    final EmbeddingProvider? embedder = _embedder;
    if (embedder == null || intent.embedding != null) return;
    if (intent.examples.isEmpty) return;
    _embeddings[intent.name] = _computeEmbedding(embedder, intent);
  }

  Future<List<double>?> _computeEmbedding(
    EmbeddingProvider embedder,
    Intent intent,
  ) async {
    try {
      final List<List<double>> vectors =
          await embedder.embedBatch(intent.examples);
      return _meanVector(vectors);
    } catch (error) {
      _emit('intent.embedding.failed', <String, Object?>{
        'name': intent.name,
        'error': '$error',
      });
      return null;
    }
  }

  RouteResult _record(RouteResult result) {
    final Intent intent = result.intent!;
    _changes.add(IntentMatched(result));
    _emit('intent.matched', <String, Object?>{
      'name': intent.name,
      'source': result.source.name,
      'confidence': result.confidence,
    });
    final Session? session = sessionOf?.call();
    if (session != null && !session.closed) {
      session.append('intent/routed', data: <String, Object?>{
        'intent': intent.name,
        'source': result.source.name,
        'confidence': result.confidence,
      });
    }
    return result;
  }

  RouteResult _miss(String input, String trimmed) {
    _changes.add(IntentMissed(input));
    _emit('intent.missed', <String, Object?>{'input': trimmed});
    return RouteResult.missed(input);
  }

  void _emit(String name, Map<String, Object?> data) =>
      telemetry?.emit(TelemetryEvent(name, data: data));
}

List<double>? _meanVector(List<List<double>> vectors) {
  final List<List<double>> usable = <List<double>>[
    for (final List<double> vector in vectors)
      if (vector.isNotEmpty) vector,
  ];
  if (usable.isEmpty) return null;
  final List<double> mean = List<double>.filled(usable.first.length, 0);
  for (final List<double> vector in usable) {
    for (var i = 0; i < mean.length; i++) {
      mean[i] += vector[i];
    }
  }
  return <double>[for (final double value in mean) value / usable.length];
}
