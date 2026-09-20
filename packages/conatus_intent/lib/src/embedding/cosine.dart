/// 余弦相似度：纯 Dart 实现，无依赖。
library;

import 'dart:math';

/// 两个等长向量的余弦相似度。
///
/// 维度不一致抛 [ArgumentError]；任一为零向量返回 `0.0`（而不是 NaN）。
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) {
    throw ArgumentError('维度不一致: ${a.length} vs ${b.length}');
  }
  var dot = 0.0;
  var normA = 0.0;
  var normB = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA == 0 || normB == 0) return 0.0;
  return dot / (sqrt(normA) * sqrt(normB));
}
