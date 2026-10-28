import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  test('withContent 替换模型可见文本并保留其余字段', () {
    final ToolResult original = ToolResult.success(
      'old',
      value: 42,
      meta: <String, Object?>{'a': 1},
      images: const <ToolImage>[
        ToolImage(mimeType: 'image/png', base64Data: 'x'),
      ],
      files: const <ToolFile>[
        ToolFile(mimeType: 'application/pdf', base64Data: 'x'),
      ],
    );

    final ToolResult updated = original.withContent('new');

    expect(updated.content, 'new');
    expect(updated.value, 42);
    expect(updated.meta, <String, Object?>{'a': 1});
    expect(updated.images, original.images);
    expect(updated.files, original.files);
    expect(updated.isError, isFalse);
  });

  test('失败结果 withContent 也保留 error', () {
    final ToolResult updated = ToolResult.failure(
      'old',
      error: const ToolError('E', 'bad'),
    ).withContent('new');

    expect(updated.content, 'new');
    expect(updated.isError, isTrue);
    expect(updated.error?.code, 'E');
  });
}
