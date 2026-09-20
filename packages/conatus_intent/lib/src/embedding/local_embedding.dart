/// 纯 Dart 的本地嵌入：字符 n-gram 哈希 + L2 归一化。
library;

import 'dart:math';

import 'embedding_provider.dart';

/// 本地嵌入提供者：离线、确定、零依赖。
///
/// 把文本小写化并剥掉空白与标点后，取字符 unigram 与 bigram，用 FNV-1a 哈希落到
/// 固定维度的桶里累加，最后 L2 归一化。两个向量的余弦因此近似等于「字符 n-gram
/// 的重叠程度」——**它只认字形重叠，不认语义**：「把灯打开」与「开灯」高分，
/// 「亮一点」与「太暗了」不会。需要真正的同义表达匹配时，注入基于模型的
/// [EmbeddingProvider]，或直接给 `Intent.embedding` 喂预计算嵌入。
///
/// 维度冲突（不同实现算出的向量不可比）由 FNV-1a 的确定性保证：同一文本、同一
/// [dimension] 永远得到同一向量，可跨进程复现。
class LocalEmbeddingProvider implements EmbeddingProvider {
  /// 构造提供者。
  LocalEmbeddingProvider({this.dimension = 256}) {
    if (dimension <= 0) {
      throw ArgumentError.value(dimension, 'dimension', '必须为正整数');
    }
  }

  /// 嵌入维度（哈希桶数）。
  @override
  final int dimension;

  @override
  Future<List<double>> embed(String text) async => _vectorOf(text);

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async =>
      <List<double>>[for (final String text in texts) _vectorOf(text)];

  @override
  void dispose() {}

  List<double> _vectorOf(String text) {
    final List<double> vector = List<double>.filled(dimension, 0);
    for (final String gram in charGrams(normalizeForEmbedding(text))) {
      vector[_fnv1a(gram) % dimension] += 1;
    }
    return _normalize(vector);
  }
}

/// 嵌入前的文本归一化：小写化、剥掉空白与标点符号。
///
/// 预计算嵌入（`Intent.embedding`）必须用同一套归一化，否则与查询不可比。
String normalizeForEmbedding(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[\s\p{P}\p{S}]+', unicode: true), '');

/// 文本的字符 unigram 与 bigram 序列。
Iterable<String> charGrams(String text) sync* {
  for (var i = 0; i < text.length; i++) {
    yield text[i];
    if (i + 1 < text.length) yield text.substring(i, i + 2);
  }
}

int _fnv1a(String text) {
  var hash = 0x811c9dc5;
  for (final int unit in text.codeUnits) {
    hash = (hash ^ unit) * 0x01000193 & 0xffffffff;
  }
  return hash;
}

List<double> _normalize(List<double> vector) {
  var norm = 0.0;
  for (final double value in vector) {
    norm += value * value;
  }
  if (norm == 0) return vector;
  final double scale = sqrt(norm);
  return <double>[for (final double value in vector) value / scale];
}
