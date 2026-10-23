import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_rag/conatus_rag.dart';
import 'package:test/test.dart';

SessionEvent ev(int seq, String type, Map<String, Object?> data) =>
    SessionEvent(
        seq: seq,
        type: type,
        time: DateTime.utc(2026, 10, 20, 14, seq),
        data: data,
        id: 'e$seq',
        sessionId: 's1');

void main() {
  final RagSource source = RagSource(
      sourceKind: 'session',
      sourceId: 's1',
      scope: RagScope(tenantId: 't1', visibilityTags: {'dept:fin'}));

  test('只索引白名单事件，保留 seq/时间/事件 id', () {
    final List<RagChunk> chunks = chunkEvents(
        source,
        <SessionEvent>[
          ev(0, kUserMessageEvent, <String, Object?>{'text': '我喜欢京剧'}),
          ev(1, kAssistantMessageEvent, <String, Object?>{'text': '记住了'}),
          ev(2, 'llm/request', <String, Object?>{'text': '不该出现'}),
        ],
        const ChunkerConfig(
            chunkChars: 200, overlapChars: 20, maxChunkChars: 300));
    expect(chunks, hasLength(1));
    expect(chunks.single.firstSeq, 0);
    expect(chunks.single.lastSeq, 1);
    expect(chunks.single.eventIds, <String>{'e0', 'e1'});
    expect(chunks.single.text, contains('京剧'));
    expect(chunks.single.text, isNot(contains('不该出现')));
    expect(chunks.single.tenantId, 't1');
  });

  test('超长工具输出按 maxChunkChars 截断并保留来源', () {
    final String huge = 'x' * 500;
    final List<RagChunk> chunks = chunkEvents(
        source,
        <SessionEvent>[
          ev(0, kToolResultEvent,
              <String, Object?>{'name': 'read', 'content': huge}),
        ],
        const ChunkerConfig(
            chunkChars: 2000, overlapChars: 20, maxChunkChars: 40));
    expect(chunks.single.text.length, lessThanOrEqualTo(80));
    expect(chunks.single.text, contains('…[截断]'));
    expect(chunks.single.citation.sourceId, 's1');
  });

  test('长会话切多块、块 id 稳定可复现', () {
    final List<SessionEvent> events = <SessionEvent>[
      for (int i = 0; i < 6; i++)
        ev(i, kUserMessageEvent, <String, Object?>{'text': '第$i条消息内容'}),
    ];
    const ChunkerConfig config =
        ChunkerConfig(chunkChars: 40, overlapChars: 8, maxChunkChars: 100);
    final List<RagChunk> first = chunkEvents(source, events, config);
    final List<RagChunk> second = chunkEvents(source, events, config);
    expect(first.length, greaterThan(1));
    expect(first.map((RagChunk c) => c.id), second.map((RagChunk c) => c.id));
    expect(first.map((RagChunk c) => c.id).toSet(), hasLength(first.length));
  });
}
