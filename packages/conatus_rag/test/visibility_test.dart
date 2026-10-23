import 'package:conatus_rag/conatus_rag.dart';
import 'package:test/test.dart';

void main() {
  group('TenantTagPolicy', () {
    test('同租户+标签交集可见，空标签 fail closed', () {
      const TenantTagPolicy policy = TenantTagPolicy();
      final RagScope fin =
          RagScope(tenantId: 't1', visibilityTags: {'dept:fin'});
      expect(policy.allows(chunk('a', 't1', {'tenant:t1', 'dept:fin'}, 0), fin),
          isTrue);
      expect(policy.allows(chunk('b', 't1', {'tenant:t1', 'dept:hr'}, 1), fin),
          isFalse);
      expect(policy.allows(chunk('c', 't2', {'tenant:t2'}, 2), fin), isFalse);
      final RagScope bare = RagScope(tenantId: 't1');
      final RagFilter filter = policy.filterFor(bare);
      expect(filter.anyTags, isEmpty);
      expect(filter.includeTenantWide, isTrue);
      expect(policy.allows(chunk('d', 't1', {'tenant:t1'}, 3), bare), isTrue);
      expect(policy.allows(chunk('x', 't1', {'tenant:t1', 'dept:hr'}, 4), bare),
          isFalse);
    });
  });
}

RagChunk chunk(String id, String tenant, Set<String> tags, int seq) => RagChunk(
      id: id,
      tenantId: tenant,
      sourceKind: 'session',
      sourceId: 's$seq',
      firstSeq: seq,
      lastSeq: seq,
      eventIds: <String>{'e$seq'},
      startTime: DateTime.utc(2026, 10, 20),
      endTime: DateTime.utc(2026, 10, 20),
      text: '正文$id',
      visibilityTags: tags,
    );
