/// 基于模型端点的嵌入提供者。
library;

import 'embedding_provider.dart';

/// 把嵌入委托给 [EmbeddingLlm] 的提供者。
///
/// [dimension] 由装配方按端点实际输出的维度声明——它只用于自检与排障，本类不会
/// 校验端点返回值。
class LlmEmbeddingProvider implements EmbeddingProvider {
  /// 构造提供者。
  const LlmEmbeddingProvider({
    required this.llm,
    this.model,
    this.dimension = 1024,
  });

  /// 嵌入端点。
  final EmbeddingLlm llm;

  /// 模型名；null 表示由端点决定。
  final String? model;

  /// 嵌入维度。
  @override
  final int dimension;

  @override
  Future<List<double>> embed(String text) => llm.embed(text, model: model);

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) =>
      Future.wait(<Future<List<double>>>[
        for (final String text in texts) embed(text),
      ]);

  @override
  void dispose() {}
}
