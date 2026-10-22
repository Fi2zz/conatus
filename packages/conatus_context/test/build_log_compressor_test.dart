import 'package:conatus_context/conatus_context.dart';
import 'package:test/test.dart';

const CompressionBudget budget = CompressionBudget(
  maxItems: 30,
  maxLines: 50,
  maxFiles: 40,
  targetRatio: 0.5,
  retrievalId: '0123456789abcdef',
);

List<String> _pytestLog() => <String>[
      'pytest run',
      for (int i = 0; i < 300; i++) 'INFO step $i',
      'ERROR test_a.py::test_x - boom',
      for (int i = 0; i < 300; i++) 'INFO more $i',
      'Traceback (most recent call last):',
      '  File "test_a.py", line 3, in test_x',
      '    assert False',
      'ERROR test_b.py::test_y - bang',
      for (int i = 0; i < 300; i++) 'INFO tail $i',
      'ERROR test_c.py::test_z - crash',
      '2 failed, 100 passed in 1.2s',
    ];

void main() {
  test('保留错误、栈与摘要', () {
    final CompressionDraft d =
        const BuildLogCompressor().compress(_pytestLog().join('\n'), budget)!;
    expect(d.output, contains('ERROR test_a.py::test_x - boom'));
    expect(d.output, contains('ERROR test_b.py::test_y - bang'));
    expect(d.output, contains('ERROR test_c.py::test_z - crash'));
    expect(d.output, contains('Traceback (most recent call last):'));
    expect(d.output, contains('File "test_a.py"'));
    expect(d.output, contains('2 failed, 100 passed'));
    expect(d.output, contains('lines omitted'));
    expect(d.unit, 'lines');
    expect(d.output.split('\n').length, lessThan(100));
  });

  test('重复 WARN 去重后只留一条', () {
    final List<String> lines = <String>[
      for (int i = 0; i < 40; i++) 'npm WARN deprecated foo: version $i',
      'npm ERR! code ELIFECYCLE',
      for (int i = 0; i < 40; i++) 'INFO filler $i',
    ];
    final CompressionDraft d =
        const BuildLogCompressor().compress(lines.join('\n'), budget)!;
    expect(RegExp(r'npm WARN').allMatches(d.output).length, 1);
    expect(d.output, contains('npm ERR! code ELIFECYCLE'));
  });

  test('cargo 错误与位置行保留', () {
    final List<String> lines = <String>[
      for (int i = 0; i < 100; i++) 'Compiling foo v$i',
      'error[E0425]: cannot find value `x`',
      ' --> src/main.rs:3:5',
      '  |',
      '3 |     x',
      '  |     ^ not found',
    ];
    final CompressionDraft d =
        const BuildLogCompressor().compress(lines.join('\n'), budget)!;
    expect(d.output, contains('error[E0425]'));
    expect(d.output, contains('--> src/main.rs:3:5'));
  });

  test('栈链跨空行继续保留后续帧', () {
    final List<String> lines = <String>[
      for (int i = 0; i < 100; i++) 'INFO noise $i',
      'ERROR boom',
      'Traceback (most recent call last):',
      '  File "a.py", line 1, in f',
      '',
      '  File "b.py", line 2, in g',
      for (int i = 0; i < 100; i++) 'INFO tail $i',
    ];
    final CompressionDraft d =
        const BuildLogCompressor().compress(lines.join('\n'), budget)!;
    expect(d.output, contains('File "b.py"'));
  });

  test('CRLF 输入保持 CRLF', () {
    final String input = '${_pytestLog().join('\r\n')}\r\n';
    final CompressionDraft d =
        const BuildLogCompressor().compress(input, budget)!;
    expect(d.output, contains('\r\n'));
    expect(d.output, contains('ERROR test_a.py::test_x - boom'));
  });
}
