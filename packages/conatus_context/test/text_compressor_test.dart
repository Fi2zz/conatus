import 'package:conatus_context/conatus_context.dart';
import 'package:test/test.dart';

const CompressionBudget budget = CompressionBudget(
  maxItems: 30,
  maxLines: 200,
  maxFiles: 40,
  targetRatio: 0.5,
  retrievalId: '0123456789abcdef',
);

void main() {
  test('连续重复行折叠并标注次数', () {
    final String input = List<String>.filled(200, 'same line').join('\n');
    final CompressionDraft d = const TextCompressor().compress(input, budget)!;
    expect(d.output, contains('same line  (×200)'));
  });

  test('UUID / 路径 / URL 行必须保留', () {
    final String input = '${List<String>.filled(200, 'filler\n').join()}'
        'id=550e8400-e29b-41d4-a716-446655440000\n'
        'path=/Users/x/project/lib/main.dart\n'
        'url=https://example.com/a\n';
    final CompressionDraft d = const TextCompressor().compress(input, budget)!;
    expect(d.output, contains('550e8400'));
    expect(d.output, contains('/Users/x/project/lib/main.dart'));
    expect(d.output, contains('https://example.com/a'));
  });

  test('收益不足返回 null', () {
    final String input =
        List<String>.generate(20, (int i) => 'path=/tmp/project/file$i.dart')
            .join('\n');
    expect(const TextCompressor().compress(input, budget), isNull);
  });

  test('连续空行折叠', () {
    final String input =
        'head\n\n\n\n\ntail\n${List<String>.filled(100, 'x').join('\n')}';
    final CompressionDraft d = const TextCompressor().compress(input, budget)!;
    expect(d.output, isNot(contains('\n\n\n')));
  });
}
