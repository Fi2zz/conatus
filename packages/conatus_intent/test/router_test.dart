import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_intent/conatus_intent.dart';
import 'package:test/test.dart';

import 'fakes.dart';

Intent _intent(
  String name, {
  List<Pattern> patterns = const <Pattern>[],
  List<String> examples = const <String>[],
  List<double>? embedding,
  int priority = 0,
}) =>
    Intent(
      name: name,
      description: name,
      patterns: patterns,
      examples: examples,
      embedding: embedding,
      priority: priority,
      action: DirectAction.respond(name),
    );

void main() {
  test('注册与注销发变更事件', () async {
    final DefaultIntentRouter router = DefaultIntentRouter();
    addTearDown(router.dispose);
    final List<IntentEvent> events = <IntentEvent>[];
    router.changes.listen(events.add);

    router.register(_intent('a'));
    expect(router.intents.map((Intent i) => i.name), <String>['a']);

    router.unregister('a');
    router.unregister('missing');
    await Future<void>.delayed(Duration.zero);

    expect(router.intents, isEmpty);
    expect(events.whereType<IntentRegistered>(), hasLength(1));
    expect(events.whereType<IntentUnregistered>(), hasLength(1));
  });

  test('重名注册抛 duplicate', () {
    final DefaultIntentRouter router = DefaultIntentRouter();
    addTearDown(router.dispose);

    router.register(_intent('a'));

    expect(
      () => router.register(_intent('a')),
      throwsA(
        isA<IntentException>()
            .having((IntentException e) => e.code, 'code', 'duplicate'),
      ),
    );
  });

  test('正则命中：来源 regex、置信度 1.0', () async {
    final DefaultIntentRouter router = DefaultIntentRouter();
    addTearDown(router.dispose);
    router.register(_intent('light_on', patterns: <Pattern>[RegExp('^开灯')]));

    final RouteResult result = await router.route('开灯');

    expect(result.matched, isTrue);
    expect(result.intent!.name, 'light_on');
    expect(result.source, RouteSource.regex);
    expect(result.confidence, 1.0);
  });

  test('空白输入直接未命中且不发事件', () async {
    final DefaultIntentRouter router = DefaultIntentRouter();
    addTearDown(router.dispose);
    final List<IntentEvent> events = <IntentEvent>[];
    router.changes.listen(events.add);

    final RouteResult result = await router.route('   ');
    await Future<void>.delayed(Duration.zero);

    expect(result.matched, isFalse);
    expect(result.input, '   ');
    expect(events, isEmpty);
  });

  test('未命中发 IntentMissed', () async {
    final DefaultIntentRouter router = DefaultIntentRouter();
    addTearDown(router.dispose);
    router.register(_intent('light_on', patterns: <Pattern>[RegExp('^开灯')]));
    final List<IntentEvent> events = <IntentEvent>[];
    router.changes.listen(events.add);

    final RouteResult result = await router.route('今天天气怎么样');
    await Future<void>.delayed(Duration.zero);

    expect(result.matched, isFalse);
    expect(result.source, RouteSource.none);
    expect(
      events.whereType<IntentMissed>().single.input,
      '今天天气怎么样',
    );
  });

  test('正则优先于向量：命中正则时根本不生成查询嵌入', () async {
    final FakeEmbedder embedder = FakeEmbedder(
      vectors: <String, List<double>>{
        '开灯': <double>[1, 0],
      },
    );
    final DefaultIntentRouter router = DefaultIntentRouter(embedder: embedder);
    addTearDown(router.dispose);
    // 预计算嵌入：注册时不发起嵌入请求，因此 embedCalls 只反映查询嵌入。
    router.register(_intent('by_vector', embedding: <double>[1, 0]));
    router.register(_intent('by_regex', patterns: <Pattern>[RegExp('^开灯')]));

    final RouteResult result = await router.route('开灯');

    expect(result.intent!.name, 'by_regex');
    expect(result.source, RouteSource.regex);
    expect(embedder.embedCalls, 0);
  });

  test('向量命中：用示例嵌入的均值', () async {
    final FakeEmbedder embedder = FakeEmbedder(
      vectors: <String, List<double>>{
        '开灯': <double>[1, 0],
        '亮一点': <double>[1, 0],
        '太暗了': <double>[1, 0],
      },
    );
    final DefaultIntentRouter router = DefaultIntentRouter(embedder: embedder);
    addTearDown(router.dispose);
    router.register(_intent('light_on', examples: <String>['亮一点', '太暗了']));

    final RouteResult result = await router.route('开灯');

    expect(result.intent!.name, 'light_on');
    expect(result.source, RouteSource.vector);
    expect(result.confidence, closeTo(1.0, 1e-9));
    expect(embedder.batchCalls, 1);
  });

  test('预计算嵌入不发起嵌入请求', () async {
    final FakeEmbedder embedder = FakeEmbedder(
      vectors: <String, List<double>>{
        '开灯': <double>[1, 0],
      },
    );
    final DefaultIntentRouter router = DefaultIntentRouter(embedder: embedder);
    addTearDown(router.dispose);
    router.register(
      _intent(
        'light_on',
        examples: <String>['亮一点'],
        embedding: <double>[1, 0],
      ),
    );

    final RouteResult result = await router.route('开灯');

    expect(result.source, RouteSource.vector);
    expect(embedder.batchCalls, 0);
  });

  test('查询嵌入失败时降级为未命中并埋点', () async {
    final InMemoryTelemetry telemetry = InMemoryTelemetry();
    final FakeEmbedder embedder = FakeEmbedder(
      failOn: '开灯',
      vectors: <String, List<double>>{
        '亮一点': <double>[1, 0],
      },
    );
    final DefaultIntentRouter router = DefaultIntentRouter(
      embedder: embedder,
      telemetry: telemetry,
    );
    addTearDown(router.dispose);
    router.register(_intent('light_on', examples: <String>['亮一点']));

    final RouteResult result = await router.route('开灯');

    expect(result.matched, isFalse);
    expect(
      telemetry.recent.map((TelemetryEvent e) => e.name),
      contains('intent.vector.failed'),
    );
  });

  test('意图嵌入生成失败时跳过该意图，正则仍可用', () async {
    final InMemoryTelemetry telemetry = InMemoryTelemetry();
    final FakeEmbedder embedder = FakeEmbedder(
      failOn: '亮一点',
      vectors: <String, List<double>>{
        '开灯': <double>[1, 0],
      },
    );
    final DefaultIntentRouter router = DefaultIntentRouter(
      embedder: embedder,
      telemetry: telemetry,
    );
    addTearDown(router.dispose);
    router.register(_intent('light_on', examples: <String>['亮一点']));
    router.register(_intent('light_off', patterns: <Pattern>[RegExp('^关灯')]));

    expect((await router.route('开灯')).matched, isFalse);
    expect((await router.route('关灯')).intent!.name, 'light_off');
    expect(
      telemetry.recent.map((TelemetryEvent e) => e.name),
      contains('intent.embedding.failed'),
    );
  });

  test('命中写入会话事件 intent/routed', () async {
    final Session session = Session(id: 'intent-test');
    final DefaultIntentRouter router =
        DefaultIntentRouter(sessionOf: () => session);
    addTearDown(router.dispose);
    router.register(_intent('light_on', patterns: <Pattern>[RegExp('^开灯')]));

    await router.route('开灯');

    expect(session.events, hasLength(1));
    expect(session.events.single.type, 'intent/routed');
    expect(session.events.single.data, <String, Object?>{
      'intent': 'light_on',
      'source': 'regex',
      'confidence': 1.0,
    });
  });

  test('会话已关闭时不写入也不抛错', () async {
    final Session session = Session(id: 'closed');
    session.close();
    final DefaultIntentRouter router =
        DefaultIntentRouter(sessionOf: () => session);
    addTearDown(router.dispose);
    router.register(_intent('light_on', patterns: <Pattern>[RegExp('^开灯')]));

    expect((await router.route('开灯')).matched, isTrue);
    expect(session.events, isEmpty);
  });

  test('埋点覆盖注册 / 注销 / 命中 / 未命中', () async {
    final InMemoryTelemetry telemetry = InMemoryTelemetry();
    final DefaultIntentRouter router =
        DefaultIntentRouter(telemetry: telemetry);
    addTearDown(router.dispose);

    router.register(_intent('light_on', patterns: <Pattern>[RegExp('^开灯')]));
    await router.route('开灯');
    await router.route('今天天气怎么样');
    router.unregister('light_on');

    expect(
      telemetry.recent.map((TelemetryEvent e) => e.name),
      <String>[
        'intent.registered',
        'intent.matched',
        'intent.missed',
        'intent.unregistered',
      ],
    );
  });

  test('dispose 释放嵌入提供者并关闭变更流', () async {
    final FakeEmbedder embedder = FakeEmbedder();
    final DefaultIntentRouter router = DefaultIntentRouter(embedder: embedder);

    final Future<void> done = router.changes.drain<void>();
    router.dispose();

    expect(embedder.disposed, isTrue);
    await done;
  });
}
