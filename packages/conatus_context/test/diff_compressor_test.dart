import 'package:conatus_context/conatus_context.dart';
import 'package:test/test.dart';

const CompressionBudget budget = CompressionBudget(
  maxItems: 30,
  maxLines: 20,
  maxFiles: 40,
  targetRatio: 0.5,
  retrievalId: '0123456789abcdef',
);

String _manyHunks(int count) => <String>[
      'diff --git a/a b/a',
      '--- a/a',
      '+++ b/a',
      for (int i = 0; i < count; i++)
        '@@ -${i * 10 + 1},3 +${i * 10 + 1},3 @@\n context\n-old$i\n+new$i',
    ].join('\n');

void main() {
  test('保留全部 +/- 行，只折叠未变更上下文', () {
    final String input = 'diff --git a/a b/a\n--- a/a\n+++ b/a\n'
        '@@ -1,20 +1,20 @@\n'
        '${List<String>.generate(10, (int i) => ' line$i').join('\n')}\n'
        '-old\n+new\n'
        '${List<String>.generate(10, (int i) => ' tail$i').join('\n')}\n';
    final CompressionDraft d = const DiffCompressor().compress(input, budget)!;
    expect(d.output, contains('-old'));
    expect(d.output, contains('+new'));
    expect(d.output, contains('context lines'));
    expect(d.unit, 'lines');
  });

  test('超过上限时保留首尾 hunk，中间整体省略', () {
    final CompressionDraft d =
        const DiffCompressor().compress(_manyHunks(20), budget)!;
    expect(d.output, contains('hunks omitted'));
    expect(d.output, contains('@@ -1,'));
    expect(d.output, contains('@@ -191,'));
  });

  test('空 diff 或非 diff 返回 null', () {
    expect(const DiffCompressor().compress('', budget), isNull);
    expect(const DiffCompressor().compress('hello', budget), isNull);
  });
}
