/// 从反复未命中的输入里提取候选意图。
library;

import 'dart:async';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_llm/conatus_llm.dart';

import 'bridges/intent_spec.dart';
import 'candidate.dart';
import 'events.dart';
import 'router.dart';

/// 让模型从未命中输入里提取候选意图的默认 system prompt。
const String kDefaultLearnerPrompt = '你是意图分析助手。分析反复出现但未被匹配的用户输入，提取可路由的候选意图。'
    '每个候选包含 name（英文 snake_case，必填）、description（中文）、'
    'patterns（正则数组）、examples（示例语句数组）。'
    '只输出 JSON，形如 {"candidates": [{"name": "check_weather"}]}。';

/// 意图学习器：记录未命中，达到次数阈值后让模型提取候选。
///
/// **只产出候选，不自动注册**——模型生成的正则可能过宽，放它自动进路由器会污染
/// 整个快路径。采纳与否由用户或部署方决定（[IntentCandidate.bind] 后自行
/// `router.register`）。
class IntentLearner {
  /// 构造学习器。
  IntentLearner({
    required this.llm,
    this.minOccurrences = 3,
    this.maxCandidates = 3,
    this.systemPrompt = kDefaultLearnerPrompt,
  }) {
    if (minOccurrences < 1) {
      throw ArgumentError.value(minOccurrences, 'minOccurrences', '必须为正整数');
    }
  }

  /// 提取候选用的模型。
  final LlmProvider llm;

  /// 触发提取的重复次数。
  final int minOccurrences;

  /// 单次提取的候选上限。
  final int maxCandidates;

  /// system prompt。
  final String systemPrompt;

  final Map<String, int> _counts = <String, int>{};
  final Map<String, String> _lastSeen = <String, String>{};

  /// 订阅路由器的未命中事件；返回撤销函数（幂等）。
  Disposer attach(IntentRouter router) {
    final StreamSubscription<IntentMissed> subscription = router.changes
        .where((IntentEvent event) => event is IntentMissed)
        .cast<IntentMissed>()
        .listen((IntentMissed event) => recordMiss(event.input));
    return subscription.cancel;
  }

  /// 记录一次未命中；空白输入被忽略。
  void recordMiss(String input) {
    final String key = _normalize(input);
    if (key.isEmpty) return;
    _counts[key] = (_counts[key] ?? 0) + 1;
    _lastSeen[key] = input;
  }

  /// 提取候选意图；没有达到阈值的输入时返回空列表。
  Future<List<IntentCandidate>> extractCandidates() async {
    final List<String> repeated = _repeated();
    if (repeated.isEmpty) return const <IntentCandidate>[];
    final LlmResult result = await llm.chat(<LlmMessage>[
      LlmMessage('system', systemPrompt),
      LlmMessage('user', _promptFor(repeated)),
    ]);
    return _parse(result.content);
  }

  /// 清空累计的未命中记录。
  void reset() {
    _counts.clear();
    _lastSeen.clear();
  }

  List<String> _repeated() => <String>[
        for (final MapEntry<String, int> entry in _counts.entries)
          if (entry.value >= minOccurrences) _lastSeen[entry.key]!,
      ];

  List<IntentCandidate> _parse(String content) {
    final Object? decoded = decodeJsonIn(content);
    final Object? items = decoded is Map ? decoded['candidates'] : decoded;
    if (items is! List) return const <IntentCandidate>[];
    final List<IntentCandidate> candidates = <IntentCandidate>[];
    for (final Object? item in items) {
      if (candidates.length >= maxCandidates) break;
      final IntentCandidate? candidate = _candidateOf(item);
      if (candidate != null) candidates.add(candidate);
    }
    return candidates;
  }

  String _promptFor(List<String> inputs) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('以下用户输入未被现有意图匹配，且反复出现：')
      ..writeln();
    for (final String input in inputs) {
      buffer.writeln('- $input');
    }
    buffer
      ..writeln()
      ..writeln('请提取 1-$maxCandidates 个候选意图。');
    return buffer.toString();
  }

  String _normalize(String input) =>
      input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

IntentCandidate? _candidateOf(Object? item) {
  if (item is! Map) return null;
  return IntentCandidate.fromSpec(
    IntentSpec.fromJson(Map<String, Object?>.from(item)),
  );
}
