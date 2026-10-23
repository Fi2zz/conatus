import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  group('ToolResult.meta', () {
    test('缺省为空，不影响既有字段', () {
      final ToolResult result = ToolResult.success('ok', value: 42);
      expect(result.meta, isEmpty);
      expect(result.value, 42);
      expect(result.isError, isFalse);
    });

    test('构造时携带元数据', () {
      final ToolResult result = ToolResult.success(
        'ok',
        meta: <String, Object?>{'cost': 0.8, 'cache': 'hit'},
      );
      expect(result.meta['cost'], 0.8);
      expect(result.meta['cache'], 'hit');
    });

    test('withMeta 合并而不丢失原有键', () {
      final ToolResult merged = ToolResult.success(
        'ok',
        meta: <String, Object?>{'cost': 0.8},
      ).withMeta(<String, Object?>{'cache': 'hit'});
      expect(merged.meta, <String, Object?>{
        'cost': 0.8,
        'cache': 'hit',
      });
      expect(merged.content, 'ok');
    });

    test('withMeta 同名键以新增值为准，失败结果同样可合并', () {
      final ToolResult failed = ToolResult.failure(
        'bad',
        error: const ToolError('E', 'bad'),
        meta: <String, Object?>{'billed': 0.2},
      ).withMeta(<String, Object?>{'billed': 0.3});
      expect(failed.meta['billed'], 0.3);
      expect(failed.isError, isTrue);
      expect(failed.error?.code, 'E');
    });
  });
}
