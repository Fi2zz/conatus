/// 嵌入生成能力缝。
///
/// 嵌入是独立的 seam：设备端不生成，可来自模型端点、构建时下发或本地实现。
library;

/// 嵌入提供者。
abstract interface class EmbeddingProvider {
  /// 嵌入维度。
  int get dimension;

  /// 生成嵌入。
  Future<List<double>> embed(String text);

  /// 批量生成。
  Future<List<List<double>>> embedBatch(List<String> texts);

  /// 释放资源。
  void dispose();
}

/// 能生成嵌入的模型端点。
///
/// `conatus_llm` 的模型接入只有 chat / chatStream，没有嵌入能力；本包不替它决定
/// 这件事，因此把嵌入端点留成独立端口，由装配方实现（例如包一层豆包的
/// `POST /api/v3/embeddings`）。
abstract interface class EmbeddingLlm {
  /// 生成 [text] 的嵌入。
  Future<List<double>> embed(String text, {String? model});
}
