import 'dart:convert';

import 'package:conatus_context/conatus_context.dart';
import 'package:test/test.dart';

const CompressionBudget _budget = CompressionBudget(
  maxItems: 30,
  maxLines: 80,
  maxFiles: 40,
  targetRatio: 0.5,
  retrievalId: '0123456789abcdef',
);

class _QualityCase {
  const _QualityCase(this.kind, this.compressor, this.input, this.mustKeep);

  final ContentKind kind;
  final ContentCompressor compressor;
  final String input;
  final String mustKeep;
}

final String _jsonSample = jsonEncode(<Map<String, Object?>>[
  for (int i = 0; i < 200; i++)
    <String, Object?>{
      'id': i,
      'status': i == 7 ? 500 : 200,
      'name': 'user-$i',
      'path': '/srv/app/data/$i.json',
    },
]);

final String _logSample = <String>[
  'pytest run',
  for (int i = 0; i < 780; i++) 'INFO step $i',
  'ERROR test_a.py::test_x - boom',
  'Traceback (most recent call last):',
  '  File "test_a.py", line 3, in test_x',
  '    assert False',
  '2 failed, 200 passed in 4.2s',
].join('\n');

final String _grepSample = <String>[
  for (int i = 1; i <= 100; i++) 'lib/a.dart:$i:match $i',
  for (int f = 0; f < 60; f++) 'lib/other$f.dart:1:hit',
].join('\n');

final String _diffSample = <String>[
  for (int f = 0; f < 12; f++)
    'diff --git a/f$f.dart b/f$f.dart\n'
        '--- a/f$f.dart\n+++ b/f$f.dart\n'
        '@@ -1,20 +1,20 @@\n'
        '${List<String>.generate(20, (int i) => ' context$i').join('\n')}\n'
        '-old$f\n+new$f',
].join('\n');

final String _csvSample = <String>[
  'id,name,score',
  for (int i = 0; i < 500; i++) '$i,user$i,${i % 100}',
].join('\n');

final String _proseSample = <String>[
  for (int i = 0; i < 400; i++)
    i.isEven
        ? 'filler line about nothing in particular'
        : 'id=550e8400-e29b-41d4-a716-44665544${i.toString().padLeft(4, '0')}',
].join('\n');

void main() {
  final List<_QualityCase> cases = <_QualityCase>[
    _QualityCase(ContentKind.jsonArray, const JsonArrayCompressor(),
        _jsonSample, '"status":500'),
    _QualityCase(
        ContentKind.buildLog, const BuildLogCompressor(), _logSample, 'ERROR'),
    _QualityCase(ContentKind.searchResults, const SearchResultsCompressor(),
        _grepSample, 'lib/a.dart:100:match 100'),
    _QualityCase(ContentKind.diff, const DiffCompressor(), _diffSample, '+new'),
    _QualityCase(ContentKind.tabular, const TabularCompressor(), _csvSample,
        'id,name,score'),
    _QualityCase(
        ContentKind.text, const TextCompressor(), _proseSample, '550e8400'),
  ];

  for (final _QualityCase c in cases) {
    test('${c.kind.name} 压缩后关键事实存活', () {
      final CompressionDraft? draft = c.compressor.compress(c.input, _budget);
      expect(draft, isNotNull);
      expect(draft!.output.length, lessThan(c.input.length * 0.85));
      expect(draft.output, contains(c.mustKeep));
    });
  }
}
