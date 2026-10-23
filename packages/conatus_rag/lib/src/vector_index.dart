import 'cosine.dart';

class VectorMatch {
  const VectorMatch({required this.id, required this.score});

  final String id;
  final double score;
}

class VectorIndex {
  VectorIndex({required this.dimension});

  final int dimension;
  final Map<String, List<double>> _vectors = <String, List<double>>{};

  int get length => _vectors.length;

  void upsert(String id, List<double> vector) {
    _checkDimension(vector);
    _vectors[id] = List<double>.unmodifiable(vector);
  }

  void remove(String id) {
    _vectors.remove(id);
  }

  List<VectorMatch> search(List<double> query, int k) {
    _checkDimension(query);
    final List<VectorMatch> matches = <VectorMatch>[
      for (final MapEntry<String, List<double>> entry in _vectors.entries)
        VectorMatch(id: entry.key, score: cosineSimilarity(query, entry.value)),
    ]..sort((VectorMatch x, VectorMatch y) => y.score.compareTo(x.score));
    return matches.take(k).toList(growable: false);
  }

  void _checkDimension(List<double> vector) {
    if (vector.length != dimension) {
      throw ArgumentError('向量维度应为 $dimension，实际为 ${vector.length}');
    }
  }
}
