/// 测试替身：脚本化模型、可控嵌入提供者。
library;

import 'package:conatus_intent/conatus_intent.dart';
import 'package:conatus_llm/conatus_llm.dart';

/// 按顺序返回预设回复的模型；记录每次请求。
///
/// 脚本耗尽时抛错，以暴露漏写的场景。
class FakeLlm implements LlmProvider {
  /// 构造替身。
  FakeLlm(this.replies);

  /// 预设回复。
  final List<String> replies;

  /// 实际收到的每次请求。
  final List<List<LlmMessage>> requests = <List<LlmMessage>>[];

  int _index = 0;

  @override
  String get name => 'fake';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    requests.add(List<LlmMessage>.of(messages));
    if (_index >= replies.length) {
      throw StateError('脚本耗尽，收到第 ${_index + 1} 次请求');
    }
    return LlmResult(
      content: replies[_index++],
      provider: 'fake',
      model: 'fake-1',
    );
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

/// 可控嵌入提供者：按文本查表，未命中给零向量。
class FakeEmbedder implements EmbeddingProvider {
  /// 构造替身。
  FakeEmbedder({
    this.vectors = const <String, List<double>>{},
    this.failOn,
    this.dimension = 2,
  });

  /// 文本 → 向量。
  final Map<String, List<double>> vectors;

  /// 命中该文本时抛错；null 表示从不失败。
  final String? failOn;

  @override
  final int dimension;

  /// `embed` 被调用的次数。
  int embedCalls = 0;

  /// `embedBatch` 被调用的次数。
  int batchCalls = 0;

  /// 是否已释放。
  bool disposed = false;

  @override
  Future<List<double>> embed(String text) async {
    embedCalls++;
    if (text == failOn) throw StateError('嵌入失败: $text');
    return vectors[text] ?? List<double>.filled(dimension, 0);
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    batchCalls++;
    return <List<double>>[for (final String text in texts) await embed(text)];
  }

  @override
  void dispose() => disposed = true;
}
