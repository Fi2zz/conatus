import 'package:conatus_context/conatus_context.dart';
import 'package:test/test.dart';

const CompressionBudget budget = CompressionBudget(
  maxItems: 30,
  maxLines: 30,
  maxFiles: 40,
  targetRatio: 0.5,
  retrievalId: '0123456789abcdef',
);

void main() {
  test('CSV 保留表头、首尾行并插入省略行', () {
    final String input = 'id,name\n'
        '${List<String>.generate(100, (int i) => '$i,n$i').join('\n')}';
    final CompressionDraft d =
        const TabularCompressor().compress(input, budget)!;
    expect(d.output.split('\n').first, 'id,name');
    expect(d.output, contains('0,n0'));
    expect(d.output, contains('99,n99'));
    expect(d.output, contains('rows omitted'));
    expect(d.unit, 'rows');
  });

  test('markdown 表格保留分隔行', () {
    final String input = '| id | name |\n'
        '|---|---|\n'
        '${List<String>.generate(60, (int i) => '| $i | n$i |').join('\n')}';
    final CompressionDraft d =
        const TabularCompressor().compress(input, budget)!;
    expect(d.output, contains('|---|---|'));
    expect(d.output, contains('| 0 | n0 |'));
    expect(d.output, contains('| 59 | n59 |'));
    final String marker = d.output
        .split('\n')
        .firstWhere((String line) => line.contains('rows omitted'));
    expect(
        '|'.allMatches(marker).length, '|'.allMatches('| id | name |').length);
  });

  test('列数不一致时返回 null（不误判）', () {
    expect(const TabularCompressor().compress('a,b\nc\n', budget), isNull);
  });

  test('行数不超过上限时返回 null', () {
    const String input = 'a,b\n1,2\n3,4\n';
    expect(const TabularCompressor().compress(input, budget), isNull);
  });
}
