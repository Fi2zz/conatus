import 'package:conatus_intent/conatus_intent.dart';
import 'package:test/test.dart';

import 'fakes.dart';

Intent _intent(
  String name, {
  List<double>? embedding,
  int priority = 0,
}) =>
    Intent(
      name: name,
      description: '',
      embedding: embedding,
      priority: priority,
      action: DirectAction.respond(name),
    );

Future<List<double>?> _embeddingOf(Intent intent) async => intent.embedding;

VectorMatcher _matcher(FakeEmbedder embedder, {double threshold = 0.85}) =>
    VectorMatcher(
      embedder: embedder,
      embeddingOf: _embeddingOf,
      threshold: threshold,
    );

void main() {
  test('相似度达标即命中', () async {
    final FakeEmbedder embedder = FakeEmbedder(
      vectors: <String, List<double>>{
        '开灯': <double>[1, 0],
      },
    );

    final RouteResult? result = await _matcher(embedder).match('开灯', <Intent>[
      _intent('light_on', embedding: <double>[1, 0]),
    ]);

    expect(result, isNotNull);
    expect(result!.intent!.name, 'light_on');
    expect(result.source, RouteSource.vector);
    expect(result.confidence, closeTo(1.0, 1e-9));
  });

  test('低于阈值不算命中', () async {
    final FakeEmbedder embedder = FakeEmbedder(
      vectors: <String, List<double>>{
        '开灯': <double>[1, 0],
      },
    );

    final RouteResult? result = await _matcher(embedder).match('开灯', <Intent>[
      _intent('light_on', embedding: <double>[0, 1]),
    ]);

    expect(result, isNull);
  });

  test('取相似度最高的意图', () async {
    final FakeEmbedder embedder = FakeEmbedder(
      vectors: <String, List<double>>{
        '开灯': <double>[0.9, 0.1],
      },
    );

    final RouteResult? result = await _matcher(embedder).match('开灯', <Intent>[
      _intent('far', embedding: <double>[1, 0]),
      _intent('near', embedding: <double>[1, 0.001]),
    ]);

    expect(result!.intent!.name, 'near');
  });

  test('同分时高优先级胜出', () async {
    final FakeEmbedder embedder = FakeEmbedder(
      vectors: <String, List<double>>{
        '开灯': <double>[1, 0],
      },
    );

    final RouteResult? result = await _matcher(embedder).match('开灯', <Intent>[
      _intent('low', embedding: <double>[1, 0]),
      _intent('high', embedding: <double>[1, 0], priority: 5),
    ]);

    expect(result!.intent!.name, 'high');
  });

  test('没有意图带嵌入时返回 null', () async {
    final FakeEmbedder embedder = FakeEmbedder();

    final RouteResult? result =
        await _matcher(embedder).match('开灯', <Intent>[_intent('no_vector')]);

    expect(result, isNull);
  });

  test('阈值可调', () async {
    final FakeEmbedder embedder = FakeEmbedder(
      vectors: <String, List<double>>{
        '开灯': <double>[1, 0],
      },
    );
    final Intent intent = _intent('light_on', embedding: <double>[0.5, 0.866]);

    expect(await _matcher(embedder).match('开灯', <Intent>[intent]), isNull);
    expect(
      await _matcher(embedder, threshold: 0.4).match('开灯', <Intent>[intent]),
      isNotNull,
    );
  });
}
