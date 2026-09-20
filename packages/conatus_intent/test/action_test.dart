import 'package:conatus_intent/conatus_intent.dart';
import 'package:test/test.dart';

void main() {
  group('RoutedAction.toJson', () {
    test('respond 动作可序列化', () {
      expect(
        const DirectAction.respond('你好，有什么可以帮你？').toJson(),
        <String, Object?>{'type': 'respond', 'text': '你好，有什么可以帮你？'},
      );
    });

    test('tool 动作可序列化', () {
      const ToolAction action = ToolAction(
        tool: 'device_control',
        argsTemplate: <String, Object?>{'device': 'light'},
      );

      expect(action.toJson(), <String, Object?>{
        'type': 'tool',
        'tool': 'device_control',
        'args': <String, Object?>{'device': 'light'},
      });
    });

    test('delegate 动作可序列化', () {
      expect(
        const DelegateAction(skill: 'code-review').toJson(),
        <String, Object?>{'type': 'delegate', 'skill': 'code-review'},
      );
    });

    test('代码闭包构造的动作抛 not-serializable', () {
      final DirectAction direct =
          DirectAction((RouteContext ctx) async => ctx.input);
      final ToolAction tool = ToolAction(
        tool: 'echo',
        args: (RouteContext ctx) => <String, Object?>{'text': ctx.input},
      );

      for (final RoutedAction action in <RoutedAction>[direct, tool]) {
        expect(
          action.toJson,
          throwsA(
            isA<IntentException>().having(
              (IntentException e) => e.code,
              'code',
              'not-serializable',
            ),
          ),
        );
      }
    });
  });

  group('ToolAction.resolveArgs', () {
    const RouteContext ctx = RouteContext(
      input: '北京天气怎么样',
      state: <String, Object?>{'city': '北京'},
    );

    test('插值 input 与 state', () {
      const ToolAction action = ToolAction(
        tool: 'weather',
        argsTemplate: <String, Object?>{
          'query': '{{input}} 天气',
          'city': '{{state.city}}',
          'unit': 'celsius',
        },
      );

      expect(action.resolveArgs(ctx), <String, Object?>{
        'query': '北京天气怎么样 天气',
        'city': '北京',
        'unit': 'celsius',
      });
    });

    test('认不出的占位符原样保留（含缺失的 state 键）', () {
      const ToolAction action = ToolAction(
        tool: 'weather',
        argsTemplate: <String, Object?>{
          'x': '{{state.missing}}',
          'y': '{{other}}'
        },
      );

      expect(action.resolveArgs(ctx), <String, Object?>{
        'x': '{{state.missing}}',
        'y': '{{other}}',
      });
    });

    test('动态 args 覆盖模板', () {
      final ToolAction action = ToolAction(
        tool: 'weather',
        argsTemplate: const <String, Object?>{'city': '上海'},
        args: (RouteContext ctx) =>
            <String, Object?>{'city': ctx.get<String>('city')},
      );

      expect(action.resolveArgs(ctx), <String, Object?>{'city': '北京'});
    });
  });

  group('interpolateArgs', () {
    test('非字符串值原样通过', () {
      expect(
        interpolateArgs(
          <String, Object?>{'n': 3, 'b': true},
          const RouteContext(input: 'x'),
        ),
        <String, Object?>{'n': 3, 'b': true},
      );
    });
  });
}
