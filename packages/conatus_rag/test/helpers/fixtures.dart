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
