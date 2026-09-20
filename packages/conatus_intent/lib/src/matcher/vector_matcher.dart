/// 向量匹配：正则覆盖不到的同义表达兜底。
library;

import '../embedding/cosine.dart';
import '../embedding/embedding_provider.dart';
import '../intent.dart';
import '../route.dart';
import 'priority.dart';

/// 解析一个意图的嵌入；返回 null 表示该意图当前不可向量匹配。
typedef EmbeddingResolver = Future<List<double>?> Function(Intent intent);

/// 向量匹配器。
class VectorMatcher {
  /// 构造匹配器。
  const VectorMatcher({
    required this.embedder,
    required this.embeddingOf,
    this.threshold = 0.85,
  });

  /// 查询嵌入的生成者。
  final EmbeddingProvider embedder;

  /// 意图嵌入的解析者。
  final EmbeddingResolver embeddingOf;

  /// 命中阈值：相似度低于它不算命中。
  final double threshold;

  /// 找相似度最高且不低于 [threshold] 的意图；没有返回 null。
  ///
  /// 遍历次序由 [orderByPriority] 决定，且只在**严格大于**当前最高分时替换，因此
  /// 同分时高优先级胜出，结果确定。
  Future<RouteResult?> match(String input, List<Intent> intents) async {
    final List<double> query = await embedder.embed(input);
    Intent? best;
    var bestScore = 0.0;
    for (final Intent intent in orderByPriority(intents)) {
      final List<double>? vector = await embeddingOf(intent);
      if (vector == null) continue;
      final double score = cosineSimilarity(query, vector);
      if (score < threshold || score <= bestScore) continue;
      best = intent;
      bestScore = score;
    }
    final Intent? matched = best;
    if (matched == null) return null;
    return RouteResult(
      intent: matched,
      confidence: bestScore,
      source: RouteSource.vector,
      input: input,
    );
  }
}
