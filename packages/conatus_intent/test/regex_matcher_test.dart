import 'package:conatus_intent/conatus_intent.dart';
import 'package:test/test.dart';

Intent _intent(
  String name, {
  List<Pattern> patterns = const <Pattern>[],
  int priority = 0,
}) =>
    Intent(
      name: name,
      description: '',
      patterns: patterns,
      priority: priority,
      action: DirectAction.respond(name),
    );

void main() {
  const RegexMatcher matcher = RegexMatcher();

  test('命中返回正则来源与 1.0 置信度', () {
    final RouteResult? result = matcher.match(
      '把灯打开',
      <Intent>[
        _intent('light_on', patterns: <Pattern>[RegExp('^把灯打开')])
      ],
    );

    expect(result, isNotNull);
    expect(result!.intent!.name, 'light_on');
    expect(result.source, RouteSource.regex);
    expect(result.confidence, 1.0);
    expect(result.input, '把灯打开');
  });

  test('未命中返回 null', () {
    expect(
      matcher.match('今天天气怎么样', <Intent>[
        _intent('light_on', patterns: <Pattern>[RegExp('^开灯')]),
      ]),
      isNull,
    );
  });

  test('没有意图时返回 null', () {
    expect(matcher.match('开灯', const <Intent>[]), isNull);
  });

  test('按 priority 降序匹配', () {
    final RouteResult? result = matcher.match('开灯', <Intent>[
      _intent('low', patterns: <Pattern>[RegExp('开灯')], priority: 1),
      _intent('high', patterns: <Pattern>[RegExp('开灯')], priority: 10),
    ]);

    expect(result!.intent!.name, 'high');
  });

  test('同 priority 保持注册顺序', () {
    final RouteResult? result = matcher.match('开灯', <Intent>[
      _intent('first', patterns: <Pattern>[RegExp('开灯')]),
      _intent('second', patterns: <Pattern>[RegExp('开灯')]),
      _intent('third', patterns: <Pattern>[RegExp('开灯')]),
    ]);

    expect(result!.intent!.name, 'first');
  });

  test('跳过没有正则的意图', () {
    final RouteResult? result = matcher.match('开灯', <Intent>[
      _intent('no_pattern'),
      _intent('with_pattern', patterns: <Pattern>[RegExp('开灯')]),
    ]);

    expect(result!.intent!.name, 'with_pattern');
  });
}
