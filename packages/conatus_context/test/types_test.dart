import 'package:conatus_context/conatus_context.dart';
import 'package:test/test.dart';

void main() {
  test('默认配置与 spec 一致', () {
    const ContextCompressionConfig c = ContextCompressionConfig();
    expect(c.enabled, true);
    expect(c.minChars, 4000);
    expect(c.minSavingRatio, 0.15);
    expect(c.ccrMaxEntries, 1000);
    expect(c.ccrTtl, const Duration(hours: 1));
    expect(c.maxSearchFiles, 40);
    expect(c.textTargetRatio, 0.5);
    expect(c.compressToolErrors, true);
  });

  test('跳过结果保留原文与长度', () {
    final ContextCompressionResult r = ContextCompressionResult.skipped(
      input: 'abc',
      kind: ContentKind.text,
      reason: 'tooSmall',
    );
    expect(r.applied, false);
    expect(r.content, 'abc');
    expect(r.beforeChars, 3);
    expect(r.afterChars, 3);
    expect(r.ccrId, isNull);
    expect(r.skippedReason, 'tooSmall');
  });

  test('统计按类型累计并标注 estimated', () {
    final CompressionStats stats = CompressionStats();
    stats.record(
      const ContextCompressionResult(
        applied: true,
        kind: ContentKind.jsonArray,
        content: 'x',
        beforeChars: 100,
        afterChars: 20,
        ccrId: 'a',
      ),
      ccrStored: true,
    );
    stats.recordFailure(ContentKind.buildLog);
    stats.countCcrHit();
    final Map<String, Object?> json = stats.toJson();
    expect(stats.applied, 1);
    expect(stats.failures, 1);
    expect(stats.ccrStored, 1);
    expect(stats.ccrHits, 1);
    expect(stats.total, 1);
    expect(json['estimated'], true);
    expect((json['byKind'] as Map<String, Object?>)['jsonArray'], isNotNull);
  });
}
