import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'rag_chunk.dart';
import 'rag_stats.dart';

/// 重排器契约：对候选集按相关性重新排序并截取 topK。
abstract interface class Reranker {
  Future<List<RagHit>> rerank(
    String query,
    List<RagHit> candidates, {
    required int topK,
  });
}

/// 不做重排，直接返回原序的前 topK 个候选。
class NoopReranker implements Reranker {
  const NoopReranker();

  @override
  Future<List<RagHit>> rerank(
    String query,
    List<RagHit> candidates, {
    required int topK,
  }) async {
    return candidates.take(topK).toList();
  }
}

/// OpenAI 风格的 HTTP 重排端点。POST `{baseUrl}/rerank`。
class HttpReranker implements Reranker {
  HttpReranker({
    required String baseUrl,
    required String model,
    required String apiKey,
    Duration timeout = const Duration(seconds: 20),
    http.Client? client,
  })  : _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _model = model,
        _apiKey = apiKey,
        _timeout = timeout,
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String _baseUrl;
  final String _model;
  final String _apiKey;
  final Duration _timeout;
  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<List<RagHit>> rerank(
    String query,
    List<RagHit> candidates, {
    required int topK,
  }) async {
    if (candidates.isEmpty) return <RagHit>[];
    final http.Response response = await _post(query, candidates, topK);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RagException(
          'rag_rerank_failed', '重排端点返回 HTTP ${response.statusCode}');
    }
    return _parse(response.body, candidates);
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<http.Response> _post(
      String query, List<RagHit> candidates, int topK) async {
    try {
      return await _client
          .post(
            Uri.parse('$_baseUrl/rerank'),
            headers: <String, String>{
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, Object?>{
              'model': _model,
              'query': query,
              'documents': <String>[
                for (final RagHit hit in candidates) hit.chunk.text
              ],
              'top_n': topK,
            }),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const RagException('rag_rerank_failed', '重排请求超时');
    } on Object catch (error) {
      throw RagException('rag_rerank_failed', '重排请求失败：${error.runtimeType}');
    }
  }

  List<RagHit> _parse(String body, List<RagHit> candidates) {
    final Object? decoded = _decode(body);
    if (decoded is! Map<String, Object?>) throw _malformed();
    final Object? results = decoded['results'];
    if (results is! List<Object?>) throw _malformed();
    final List<RagHit> ranked = <RagHit>[];
    for (final Object? item in results) {
      final (int index, double score) = _entry(item);
      if (index < 0 || index >= candidates.length) throw _malformed();
      ranked.add(RagHit(
        chunk: candidates[index].chunk,
        score: candidates[index].score,
        rerankScore: score,
      ));
    }
    return ranked;
  }

  (int, double) _entry(Object? item) {
    if (item is! Map<String, Object?>) throw _malformed();
    final Object? index = item['index'];
    final Object? score = item['relevance_score'];
    if (index is! int || score is! num) throw _malformed();
    return (index, score.toDouble());
  }

  Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw _malformed();
    }
  }

  RagException _malformed() =>
      const RagException('rag_rerank_failed', '重排响应格式不合法');
}
