import 'package:conatus_rag/conatus_rag.dart';
import 'package:test/test.dart';

void main() {
  test('向量索引按余弦排序、截断 k、支持删除', () {
    final VectorIndex index = VectorIndex(dimension: 2);
    index.upsert('a', <double>[1, 0]);
    index.upsert('b', <double>[0, 1]);
    index.upsert('c', <double>[0.9, 0.1]);
    expect(index.search(<double>[1, 0], 2).map((VectorMatch m) => m.id),
        <String>['a', 'c']);
    index.remove('a');
    expect(index.length, 2);
    expect(index.search(<double>[1, 0], 5), hasLength(2));
  });

  test('余弦与维度校验', () {
    expect(cosineSimilarity(<double>[1, 0], <double>[0, 1]), 0);
    expect(cosineSimilarity(<double>[0, 0], <double>[1, 0]), 0);
    expect(() => cosineSimilarity(<double>[1], <double>[1, 2]),
        throwsArgumentError);
    expect(() => VectorIndex(dimension: 2).upsert('x', <double>[1]),
        throwsArgumentError);
  });
}
