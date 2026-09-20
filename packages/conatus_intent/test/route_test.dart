import 'package:conatus_intent/conatus_intent.dart';
import 'package:test/test.dart';

void main() {
  group('RouteResult', () {
    test('missed 返回空结果', () {
      final RouteResult result = RouteResult.missed('随便说点什么');

      expect(result.matched, isFalse);
      expect(result.intent, isNull);
      expect(result.confidence, 0.0);
      expect(result.source, RouteSource.none);
      expect(result.input, '随便说点什么');
    });

    test('命中时 matched 为真', () {
      const Intent intent = Intent(
        name: 'ping',
        description: '',
        action: DirectAction.respond('pong'),
      );
      const RouteResult result = RouteResult(
        intent: intent,
        confidence: 1.0,
        source: RouteSource.regex,
      );

      expect(result.matched, isTrue);
      expect(result.source, RouteSource.regex);
      expect(result.input, isNull);
    });
  });

  group('RouteContext', () {
    test('get 读状态里的值', () {
      const RouteContext ctx = RouteContext(
        input: '开灯',
        state: <String, Object?>{'room': 'living', 'level': 3},
      );

      expect(ctx.input, '开灯');
      expect(ctx.get<String>('room'), 'living');
      expect(ctx.get<int>('level'), 3);
      expect(ctx.get<String>('missing'), isNull);
    });

    test('缺省状态为空', () {
      expect(const RouteContext(input: 'x').state, isEmpty);
    });
  });

  group('RouteSource', () {
    test('三种来源各有名字', () {
      expect(
        RouteSource.values.map((RouteSource s) => s.name),
        <String>['regex', 'vector', 'none'],
      );
    });
  });
}
