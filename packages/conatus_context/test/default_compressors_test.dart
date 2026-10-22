import 'package:conatus_context/conatus_context.dart';
import 'package:test/test.dart';

void main() {
  test('默认集合覆盖六类内容', () {
    final Set<ContentKind> kinds = defaultContentCompressors()
        .map((ContentCompressor compressor) => compressor.kind)
        .toSet();
    expect(kinds, <ContentKind>{
      ContentKind.jsonArray,
      ContentKind.buildLog,
      ContentKind.searchResults,
      ContentKind.diff,
      ContentKind.tabular,
      ContentKind.text,
    });
  });

  test('Router 缺省使用默认集合压缩 JSON', () async {
    final ContextRouter router = ContextRouter(
      config: const ContextCompressionConfig(minChars: 100),
      store: CcrMemoryStore(),
    );
    final String input =
        '[${List<String>.generate(200, (int i) => '{"id":$i}').join(',')}]';
    final ContextCompressionResult r =
        await router.compress(input, toolName: 't');
    expect(r.applied, true);
    expect(r.kind, ContentKind.jsonArray);
  });
}
