import 'package:conatus_intent/conatus_intent.dart';
import 'package:test/test.dart';

class _EmbeddingLlm implements EmbeddingLlm {
  _EmbeddingLlm() : vector = const <double>[1, 2, 3];

  final List<double> vector;
  final List<String> calls = <String>[];

  @override
  Future<List<double>> embed(String text, {String? model}) async {
    calls.add('${model ?? '-'}:$text');
    return vector;
  }
}

void main() {
  group('cosineSimilarity', () {
    test('同向向量为 1，正交为 0', () {
      expect(
          cosineSimilarity(<double>[1, 0], <double>[2, 0]), closeTo(1.0, 1e-9));
      expect(
          cosineSimilarity(<double>[1, 0], <double>[0, 1]), closeTo(0.0, 1e-9));
    });

    test('维度不一致抛 ArgumentError', () {
      expect(
        () => cosineSimilarity(<double>[1, 0], <double>[1]),
        throwsArgumentError,
      );
    });

    test('零向量返回 0 而不是 NaN', () {
      expect(cosineSimilarity(<double>[0, 0], <double>[1, 0]), 0.0);
    });
  });

  group('normalizeForEmbedding', () {
    test('小写化并剥掉空白与标点', () {
      expect(normalizeForEmbedding(' Hello, World! '), 'helloworld');
      expect(normalizeForEmbedding('开灯。'), '开灯');
    });
  });

  group('charGrams', () {
    test('产出 unigram 与 bigram', () {
      expect(charGrams('abc').toList(), <String>['a', 'ab', 'b', 'bc', 'c']);
      expect(charGrams('').toList(), isEmpty);
      expect(charGrams('a').toList(), <String>['a']);
    });
  });

  group('LocalEmbeddingProvider', () {
    test('维度正确、已归一化、可复现', () async {
      final LocalEmbeddingProvider provider =
          LocalEmbeddingProvider(dimension: 64);

      final List<double> first = await provider.embed('把灯打开');
      final List<double> second = await provider.embed('把灯打开');

      expect(first, hasLength(64));
      expect(first, second);
      expect(cosineSimilarity(first, second), closeTo(1.0, 1e-9));
    });

    test('字形重叠的文本更接近', () async {
      final LocalEmbeddingProvider provider = LocalEmbeddingProvider();

      final List<double> query = await provider.embed('开灯');
      final double near = cosineSimilarity(query, await provider.embed('把灯打开'));
      final double far = cosineSimilarity(query, await provider.embed('明天开会'));

      expect(near, greaterThan(far));
      expect(near, greaterThan(0.0));
    });

    test('空文本得到零向量（相似度为 0）', () async {
      final LocalEmbeddingProvider provider = LocalEmbeddingProvider();

      expect(
        cosineSimilarity(
          await provider.embed(''),
          await provider.embed('开灯'),
        ),
        0.0,
      );
    });

    test('非正维度抛 ArgumentError', () {
      expect(() => LocalEmbeddingProvider(dimension: 0), throwsArgumentError);
    });

    test('embedBatch 按顺序返回', () async {
      final LocalEmbeddingProvider provider = LocalEmbeddingProvider();

      final List<List<double>> batch =
          await provider.embedBatch(<String>['开灯', '关灯']);

      expect(batch, hasLength(2));
      expect(batch.first, await provider.embed('开灯'));
      expect(batch.last, await provider.embed('关灯'));
    });
  });

  group('LlmEmbeddingProvider', () {
    test('把嵌入委托给端点并透传模型名', () async {
      final _EmbeddingLlm llm = _EmbeddingLlm();
      final LlmEmbeddingProvider provider = LlmEmbeddingProvider(
          llm: llm, model: 'doubao-embedding', dimension: 3);

      expect(provider.dimension, 3);
      expect(await provider.embed('开灯'), <double>[1, 2, 3]);
      expect(llm.calls, <String>['doubao-embedding:开灯']);
    });

    test('embedBatch 逐个委托', () async {
      final _EmbeddingLlm llm = _EmbeddingLlm();
      final LlmEmbeddingProvider provider = LlmEmbeddingProvider(llm: llm);

      final List<List<double>> batch =
          await provider.embedBatch(<String>['开灯', '关灯']);

      expect(batch, hasLength(2));
      expect(llm.calls, <String>['-:开灯', '-:关灯']);
    });
  });
}
