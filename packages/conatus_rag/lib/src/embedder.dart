import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'rag_stats.dart';

/// 嵌入契约：把文本映射为固定维度的稠密向量。
abstract interface class Embedder {
  String get model;
  int get dimension;
  Future<List<double>> embed(String text);
  Future<List<List<double>>> embedBatch(List<String> texts);
  void dispose();
}

/// OpenAI 兼容的 `POST {baseUrl}/embeddings` 嵌入端点。
/// 错误统一抛 `rag_embed_failed`，消息只含状态码、维度或失败类型，不含 [apiKey]。
class OpenAiEmbedder implements Embedder {
  OpenAiEmbedder({
    required String baseUrl,
    required String model,
    required String apiKey,
    required int dimension,
    int batchSize = 16,
    http.Client? client,
  })  : _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _model = model,
        _apiKey = apiKey,
        _dimension = dimension,
        _batchSize = batchSize,
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String _baseUrl;
  final String _model;
  final String _apiKey;
  final int _dimension;
  final int _batchSize;
  final http.Client _client;
  final bool _ownsClient;

  @override
  String get model => _model;

  @override
  int get dimension => _dimension;

  @override
  Future<List<double>> embed(String text) async {
    final List<List<double>> vectors = await embedBatch(<String>[text]);
    return vectors.first;
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    final List<List<double>> vectors = <List<double>>[];
    for (int start = 0; start < texts.length; start += _batchSize) {
      final int end = math.min(start + _batchSize, texts.length);
      vectors.addAll(await _embedChunk(texts.sublist(start, end)));
    }
    return vectors;
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<List<List<double>>> _embedChunk(List<String> input) async {
    final http.Response response = await _post(input);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RagException(
        'rag_embed_failed',
        '嵌入端点返回 HTTP ${response.statusCode}',
      );
    }
    return _parseVectors(response.body, input.length);
  }

  Future<http.Response> _post(List<String> input) async {
    try {
      return await _client.post(
        Uri.parse('$_baseUrl/embeddings'),
        headers: <String, String>{
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(<String, Object?>{'model': _model, 'input': input}),
      );
    } on Object catch (error) {
      throw RagException(
        'rag_embed_failed',
        '嵌入请求失败：${error.runtimeType}',
      );
    }
  }

  List<List<double>> _parseVectors(String body, int expected) {
    final List<Object?> data = _dataOf(_decode(body));
    if (data.length != expected) throw _malformed();
    final List<List<double>?> slots =
        List<List<double>?>.filled(expected, null);
    for (final Object? item in data) {
      final (int index, List<double> vector) = _entryOf(item);
      if (index < 0 || index >= expected || slots[index] != null) {
        throw _malformed();
      }
      slots[index] = vector;
    }
    return slots.cast<List<double>>();
  }

  Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw _malformed();
    }
  }

  List<Object?> _dataOf(Object? decoded) {
    if (decoded is! Map<String, Object?>) throw _malformed();
    final Object? data = decoded['data'];
    if (data is! List<Object?>) throw _malformed();
    return data;
  }

  (int, List<double>) _entryOf(Object? item) {
    if (item is! Map<String, Object?>) throw _malformed();
    final Object? index = item['index'];
    if (index is! int) throw _malformed();
    return (index, _vectorOf(item['embedding']));
  }

  List<double> _vectorOf(Object? raw) {
    if (raw is! List<Object?>) throw _malformed();
    final List<double> vector = <double>[];
    for (final Object? value in raw) {
      if (value is! num) throw _malformed();
      vector.add(value.toDouble());
    }
    if (vector.length != _dimension) {
      throw RagException(
        'rag_embed_failed',
        '向量维度 ${vector.length} 与配置的 $_dimension 不符',
      );
    }
    return vector;
  }

  RagException _malformed() =>
      const RagException('rag_embed_failed', '嵌入响应格式不合法');
}
