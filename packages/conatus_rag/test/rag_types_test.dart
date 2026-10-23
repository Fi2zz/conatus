import 'package:conatus_rag/conatus_rag.dart';
import 'package:test/test.dart';

void main() {
  test('RagScope 自动补租户标签并拒绝空租户', () {
    final RagScope scope = RagScope(
        tenantId: 't1', principalId: 'u1', visibilityTags: {'dept:fin'});
    expect(
        scope.visibilityTags, containsAll(<String>['tenant:t1', 'dept:fin']));
    expect(() => RagScope(tenantId: '  '), throwsArgumentError);
  });

  test('RagChunk JSON 往返保留 citation 与时间', () {
    final RagChunk chunk = RagChunk(
      id: 'session/s1/0-3',
      tenantId: 't1',
      sourceKind: 'session',
      sourceId: 's1',
      firstSeq: 0,
      lastSeq: 3,
      eventIds: {'e1', 'e2'},
      startTime: DateTime.utc(2026, 10, 20, 14, 3),
      endTime: DateTime.utc(2026, 10, 20, 14, 9),
      text: '用户：你好',
    );
    final RagChunk back = RagChunk.fromJson(chunk.toJson());
    expect(back.citation.sourceId, 's1');
    expect(back.citation.firstSeq, 0);
    expect(back.startTime, DateTime.utc(2026, 10, 20, 14, 3));
    expect(back.eventIds, <String>{'e1', 'e2'});
  });

  test('estimateTokens 对空串为 0、对中文按 2 字 1 token 保守估计', () {
    expect(estimateTokens(''), 0);
    expect(estimateTokens('一二三四'), 2);
  });

  test('RagStats.zero 全为 0，RagException 带错误码', () {
    expect(RagStats.zero().retrievals, 0);
    expect(const RagException('rag_x', '坏了').toString(), contains('rag_x'));
  });
}
