/// 记忆探针的度量：字符 n-gram 余弦与 Wilson 上界。
library;

import 'dart:math' as math;

/// 「语义相关」的余弦阈值（近似 embedding 能看到的相似度）。
const double relevantCos = 0.45;

/// 字符 unigram + bigram 余弦相似度。
double cosineOf(String a, String b) {
  final Map<String, int> left = _grams(a);
  final Map<String, int> right = _grams(b);
  if (left.isEmpty || right.isEmpty) return 0;
  double dot = 0;
  left.forEach((String gram, int count) {
    dot += count * (right[gram] ?? 0);
  });
  return dot / (_norm(left) * _norm(right));
}

/// 二项比例的 95% Wilson 置信上界。
double wilsonUpper(int k, int n) {
  if (n == 0) return 1;
  const double z = 1.96;
  final double p = k / n;
  final double d = 1 + z * z / n;
  final double c = p + z * z / (2 * n);
  final double r = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n));
  return (c + r) / d;
}

Map<String, int> _grams(String text) {
  final String clean = text.toLowerCase().replaceAll(
    RegExp(r'[^\w\u4e00-\u9fff]'),
    '',
  );
  final Map<String, int> grams = <String, int>{};
  for (int i = 0; i < clean.length; i++) {
    grams[clean[i]] = (grams[clean[i]] ?? 0) + 1;
    if (i + 1 < clean.length) {
      final String bigram = clean.substring(i, i + 2);
      grams[bigram] = (grams[bigram] ?? 0) + 1;
    }
  }
  return grams;
}

double _norm(Map<String, int> grams) =>
    math.sqrt(grams.values.fold<double>(0, (double n, int v) => n + v * v));
