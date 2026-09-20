import 'package:conatus_intent/conatus_intent.dart';
import 'package:test/test.dart';

RoutedAction buildAction(Map<String, Object?> json) {
  final String type = json['type'] as String;
  switch (type) {
    case 'tool':
      return ToolAction(
        tool: json['tool'] as String,
        argsTemplate: Map<String, Object?>.from(json['args'] as Map),
      );
    case 'respond':
      return DirectAction.respond(json['text'] as String);
    default:
      return DelegateAction(skill: json['skill'] as String);
  }
}

Intent sampleIntent() => Intent(
      name: 'light_on',
      description: '开灯',
      patterns: <Pattern>[RegExp(r'^(开灯|把灯打开)')],
      examples: <String>['亮一点', '太暗了'],
      embedding: <double>[0.5, 0.5],
      priority: 10,
      action: const ToolAction(
        tool: 'device_control',
        argsTemplate: <String, Object?>{'device': 'light', 'op': 'on'},
      ),
    );

void main() {
  group('Intent', () {
    test('JSON 往返一致', () {
      final Intent intent = sampleIntent();

      final Intent restored = Intent.fromJson(
        intent.toJson(),
        actionBuilder: buildAction,
      );

      expect(restored.name, intent.name);
      expect(restored.description, intent.description);
      expect(restored.examples, intent.examples);
      expect(restored.embedding, intent.embedding);
      expect(restored.priority, intent.priority);
      expect(restored.patterns, hasLength(1));
      expect((restored.patterns.single as RegExp).pattern, r'^(开灯|把灯打开)');
      expect(restored.action, isA<ToolAction>());
      expect(restored.toJson(), intent.toJson());
    });

    test('省略可选字段后往返仍一致', () {
      const Intent intent = Intent(
        name: 'ping',
        description: '',
        action: DirectAction.respond('pong'),
      );

      final Intent restored = Intent.fromJson(
        intent.toJson(),
        actionBuilder: buildAction,
      );

      expect(restored.priority, 0);
      expect(restored.patterns, isEmpty);
      expect(restored.examples, isEmpty);
      expect(restored.embedding, isNull);
      expect(restored.toJson(), intent.toJson());
    });

    test('hasPatterns / hasVector 反映触发条件', () {
      expect(sampleIntent().hasPatterns, isTrue);
      expect(sampleIntent().hasVector, isTrue);
      expect(
        const Intent(
                name: 'x', description: '', action: DirectAction.respond(''))
            .hasVector,
        isFalse,
      );
    });

    test('缺少 action 抛 IntentException', () {
      expect(
        () => Intent.fromJson(
          <String, Object?>{'name': 'x'},
          actionBuilder: buildAction,
        ),
        throwsA(
          isA<IntentException>()
              .having((IntentException e) => e.code, 'code', 'missing-field'),
        ),
      );
    });

    test('非 RegExp 模式无法序列化', () {
      final Intent intent = Intent(
        name: 'x',
        description: '',
        patterns: <Pattern>[_FakePattern()],
        action: const DirectAction.respond('ok'),
      );

      expect(
        intent.toJson,
        throwsA(
          isA<IntentException>().having(
              (IntentException e) => e.code, 'code', 'not-serializable'),
        ),
      );
    });
  });
}

class _FakePattern implements Pattern {
  @override
  Iterable<Match> allMatches(String string, [int start = 0]) => const <Match>[];

  @override
  Match? matchAsPrefix(String string, [int start = 0]) => null;
}
