import 'package:conatus_context/conatus_context.dart';
import 'package:test/test.dart';

const CompressionBudget budget = CompressionBudget(
  maxItems: 30,
  maxLines: 10,
  maxFiles: 40,
  targetRatio: 0.5,
  retrievalId: '0123456789abcdef',
);

void main() {
  test('每文件保留首尾匹配并汇总省略数', () {
    final String input = <String>[
      for (int i = 1; i <= 100; i++) 'lib/a.dart:$i:match $i',
    ].join('\n');
    final CompressionDraft d =
        const SearchResultsCompressor().compress(input, budget)!;
    expect(d.output, contains('lib/a.dart:1:match 1'));
    expect(d.output, contains('lib/a.dart:100:match 100'));
    expect(d.output, contains('more matches in lib/a.dart'));
    expect(d.unit, 'matches');
  });

  test('错误行优先保留', () {
    final String input = <String>[
      for (int i = 1; i <= 10; i++) 'lib/a.dart:$i:match $i',
      'lib/a.dart:11:ERROR boom',
      for (int i = 12; i <= 21; i++) 'lib/a.dart:$i:match $i',
    ].join('\n');
    final CompressionDraft d =
        const SearchResultsCompressor().compress(input, budget)!;
    expect(d.output, contains('ERROR boom'));
  });

  test('文件数超过上限时按匹配数截断并汇总', () {
    final String input = <String>[
      for (int f = 0; f < 5; f++)
        for (int i = 1; i <= f + 2; i++) 'lib/f$f.dart:$i:match',
    ].join('\n');
    const CompressionBudget small = CompressionBudget(
      maxItems: 30,
      maxLines: 30,
      maxFiles: 2,
      targetRatio: 0.5,
      retrievalId: '0123456789abcdef',
    );
    final CompressionDraft d =
        const SearchResultsCompressor().compress(input, small)!;
    expect(d.output, contains('more files with'));
  });

  test('非匹配行以省略提示保留', () {
    final String input = <String>[
      for (int i = 1; i <= 10; i++) 'lib/a.dart:$i:match $i',
      '10 matches found in 1 file',
    ].join('\n');
    final CompressionDraft d =
        const SearchResultsCompressor().compress(input, budget)!;
    expect(d.output, contains('non-match lines omitted'));
  });

  test('ripgrep 上下文格式与 Windows 路径可解析', () {
    final String input = <String>[
      r'C:\src\pre-commit.dart-12-before',
      r'C:\src\pre-commit.dart:13:match',
      r'C:\src\pre-commit.dart-14-after',
      r'C:\src\pre-commit.dart:15:match',
    ].join('\n');
    final CompressionDraft d =
        const SearchResultsCompressor().compress(input, budget)!;
    expect(d.output, contains(r'C:\src\pre-commit.dart:13:match'));
  });
}
