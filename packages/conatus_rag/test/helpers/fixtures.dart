import 'package:conatus_rag/conatus_rag.dart';

RagChunk chunk(String id, String tenant, Set<String> tags, int seq,
        {String? text, DateTime? time}) =>
    RagChunk(
      id: id,
      tenantId: tenant,
      sourceKind: 'session',
      sourceId: 's$seq',
      firstSeq: seq,
      lastSeq: seq,
      eventIds: <String>{'e$seq'},
      startTime: time ?? DateTime.utc(2026, 10, 20),
      endTime: time ?? DateTime.utc(2026, 10, 20),
      text: text ?? '正文$id',
      visibilityTags: tags,
    );

/// 确定性的假嵌入器：把任意文本映射到固定二维向量，供离线测试使用。
class FakeEmbedder implements Embedder {
  @override
  String get model => 'fake';

  @override
  int get dimension => 2;

  @override
  Future<List<double>> embed(String text) async => <double>[1, 0];

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async =>
      <List<double>>[
        for (final String _ in texts) <double>[1, 0],
      ];

  @override
  void dispose() {}
}
