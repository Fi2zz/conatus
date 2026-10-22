import 'dart:convert';

import 'package:conatus_context/conatus_context.dart';
import 'package:test/test.dart';

const CompressionBudget budget = CompressionBudget(
  maxItems: 10,
  maxLines: 100,
  maxFiles: 10,
  targetRatio: 0.5,
  retrievalId: '0123456789abcdef',
);

void main() {
  test('保留错误项与首尾项，输出仍是合法 JSON', () {
    final List<Map<String, Object?>> items = <Map<String, Object?>>[
      for (int i = 0; i < 100; i++)
        <String, Object?>{
          'id': i,
          'status': i == 50 ? 500 : 200,
          'name': 'n$i',
        },
    ];
    final CompressionDraft draft =
        const JsonArrayCompressor().compress(jsonEncode(items), budget)!;
    final List<Object?> decoded = jsonDecode(draft.output) as List<Object?>;
    expect(decoded.length, lessThanOrEqualTo(11));
    expect(draft.output, contains('"status":500'));
    expect(draft.output, contains('"id":0'));
    expect(draft.output, contains('"id":99'));
    expect(draft.output, contains('<<ctx:0123456789abcdef'));
    expect(draft.itemsOmitted, greaterThan(0));
    expect(draft.unit, 'items');
  });

  test('保留数值字段的极端异常项', () {
    final List<Map<String, Object?>> items = <Map<String, Object?>>[
      for (int i = 0; i < 100; i++)
        <String, Object?>{'id': i, 'latency': i == 40 ? 999999 : 10},
    ];
    final CompressionDraft draft =
        const JsonArrayCompressor().compress(jsonEncode(items), budget)!;
    expect(draft.output, contains('999999'));
  });

  test('重复字符串去重并保持顺序', () {
    final String input = jsonEncode(<String>[
      for (int i = 0; i < 50; i++) i.isEven ? 'same' : 'v$i',
    ]);
    final CompressionDraft draft =
        const JsonArrayCompressor().compress(input, budget)!;
    expect(draft.output.split('"same"').length - 1, 1);
  });

  test('深度超过 32 的 JSON 透传', () {
    final String deep = '${List<String>.filled(40, '[').join()}1'
        '${List<String>.filled(40, ']').join()}';
    expect(const JsonArrayCompressor().compress(deep, budget), isNull);
  });

  test('非法 JSON 返回 null', () {
    expect(const JsonArrayCompressor().compress('[1,2', budget), isNull);
    expect(const JsonArrayCompressor().compress('{"a":1}', budget), isNull);
  });

  test('元素不超过上限时只紧凑化，不省略', () {
    final CompressionDraft draft = const JsonArrayCompressor()
        .compress('[ {"a": 1} , {"a": 2} ]', budget)!;
    expect(draft.itemsOmitted, 0);
    expect(draft.output, '[{"a":1},{"a":2}]');
  });

  test('关闭 CCR 时说明项不含 id', () {
    const CompressionBudget noCcr = CompressionBudget(
      maxItems: 2,
      maxLines: 10,
      maxFiles: 10,
      targetRatio: 0.5,
      retrievalId: '',
    );
    final CompressionDraft draft = const JsonArrayCompressor().compress(
      jsonEncode(<Map<String, Object?>>[
        for (int i = 0; i < 10; i++) <String, Object?>{'id': i},
      ]),
      noCcr,
    )!;
    expect(draft.output, isNot(contains('<<ctx:')));
    expect(draft.output, contains('items omitted'));
  });
}
