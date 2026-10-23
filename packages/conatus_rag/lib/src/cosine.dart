import 'dart:math' as math;

double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) {
    throw ArgumentError('向量维度不一致：${a.length} != ${b.length}');
  }
  double dot = 0;
  double normA = 0;
  double normB = 0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA == 0 || normB == 0) {
    return 0.0;
  }
  return dot / (math.sqrt(normA) * math.sqrt(normB));
}
