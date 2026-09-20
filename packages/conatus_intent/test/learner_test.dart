import 'package:conatus_intent/conatus_intent.dart';
import 'package:test/test.dart';

import 'fakes.dart';

const String _candidatesJson = '''
以下是候选：
```json
{"candidates": [
  {"name": "check_weather", "description": "查天气",
   "patterns": ["^(查天气|天气怎么样)"], "examples": ["今天天气"]},
  {"name": "bad", "patterns": ["[未闭合"], "examples": ["坏模式"]},
  {"description": "没有名字", "patterns": ["x"]}
]}
```
''';

void main() {
  group('IntentLearner', () {
    test('未达阈值时不调用模型', () async {
      final FakeLlm llm = FakeLlm(<String>[]);
      final IntentLearner learner = IntentLearner(llm: llm);

      learner.recordMiss('今天天气怎么样');
      learner.recordMiss('今天天气怎么样');

      expect(await learner.extractCandidates(), isEmpty);
      expect(llm.requests, isEmpty);
    });

    test('归一化后计数：大小写与空白等价', () async {
      final FakeLlm llm = FakeLlm(<String>[_candidatesJson]);
      final IntentLearner learner = IntentLearner(llm: llm, minOccurrences: 2);

      learner.recordMiss('Hello  World');
      learner.recordMiss('  hello world ');

      final List<IntentCandidate> candidates =
          await learner.extractCandidates();
      expect(candidates, isNotEmpty);
      expect(llm.requests.single.last.content, contains('hello world'));
    });

    test('空白输入被忽略', () {
      final FakeLlm llm = FakeLlm(<String>[]);
      final IntentLearner learner = IntentLearner(llm: llm, minOccurrences: 1);

      learner.recordMiss('   ');

      expect(learner.extractCandidates(), completion(isEmpty));
    });

    test('提取候选：丢弃非法正则与缺名候选，保序并限量', () async {
      final FakeLlm llm = FakeLlm(<String>[_candidatesJson]);
      final IntentLearner learner = IntentLearner(llm: llm, minOccurrences: 1);

      learner.recordMiss('今天天气怎么样');

      final List<IntentCandidate> candidates =
          await learner.extractCandidates();

      expect(
        candidates.map((IntentCandidate c) => c.name),
        <String>['check_weather', 'bad'],
      );
      expect(candidates.first.patterns, hasLength(1));
      expect(candidates.first.examples, <String>['今天天气']);
      // `[未闭合` 编译失败，但示例仍在，因此候选保留。
      expect(candidates.last.patterns, isEmpty);
      expect(candidates.last.examples, <String>['坏模式']);
    });

    test('maxCandidates 限制产出数量', () async {
      final FakeLlm llm = FakeLlm(<String>[_candidatesJson]);
      final IntentLearner learner = IntentLearner(
        llm: llm,
        minOccurrences: 1,
        maxCandidates: 1,
      );

      learner.recordMiss('今天天气怎么样');

      expect(await learner.extractCandidates(), hasLength(1));
    });

    test('模型输出解析不出时返回空列表', () async {
      final FakeLlm llm = FakeLlm(<String>['完全没有 JSON']);
      final IntentLearner learner = IntentLearner(llm: llm, minOccurrences: 1);

      learner.recordMiss('今天天气怎么样');

      expect(await learner.extractCandidates(), isEmpty);
    });

    test('reset 清空记录', () async {
      final FakeLlm llm = FakeLlm(<String>[_candidatesJson]);
      final IntentLearner learner = IntentLearner(llm: llm, minOccurrences: 1);
      learner.recordMiss('今天天气怎么样');

      learner.reset();

      expect(await learner.extractCandidates(), isEmpty);
    });

    test('非正阈值抛 ArgumentError', () {
      expect(
        () => IntentLearner(llm: FakeLlm(<String>[]), minOccurrences: 0),
        throwsArgumentError,
      );
    });

    test('attach 订阅路由器的未命中事件', () async {
      final DefaultIntentRouter router = DefaultIntentRouter();
      addTearDown(router.dispose);
      router.register(Intent(
        name: 'ping',
        description: '',
        patterns: <Pattern>[RegExp('^ping')],
        action: const DirectAction.respond('pong'),
      ));
      final FakeLlm llm = FakeLlm(<String>[_candidatesJson]);
      final IntentLearner learner = IntentLearner(llm: llm, minOccurrences: 2);

      learner.attach(router);
      await router.route('今天天气怎么样');
      await router.route('今天天气怎么样');
      await Future<void>.delayed(Duration.zero);

      expect(await learner.extractCandidates(), isNotEmpty);
    });

    test('attach 返回的撤销函数停止订阅', () async {
      final DefaultIntentRouter router = DefaultIntentRouter();
      addTearDown(router.dispose);
      final FakeLlm llm = FakeLlm(<String>[_candidatesJson]);
      final IntentLearner learner = IntentLearner(llm: llm, minOccurrences: 1);

      final void Function() detach = learner.attach(router);
      detach();
      await router.route('今天天气怎么样');
      await Future<void>.delayed(Duration.zero);

      expect(await learner.extractCandidates(), isEmpty);
    });
  });

  group('IntentCandidate', () {
    test('bind 产出可注册的 Intent', () {
      const IntentCandidate candidate = IntentCandidate(
        name: 'check_weather',
        description: '查天气',
        examples: <String>['今天天气'],
      );

      final Intent intent = candidate.bind(
        const ToolAction(tool: 'weather_now'),
      );

      expect(intent.name, 'check_weather');
      expect(intent.examples, <String>['今天天气']);
      expect(intent.action, isA<ToolAction>());
    });

    test('toJson 丢掉非 RegExp 模式', () {
      final IntentCandidate candidate = IntentCandidate(
        name: 'x',
        description: '',
        patterns: <Pattern>[RegExp('^a'), _OtherPattern()],
      );

      expect(candidate.toJson()['patterns'], <String>['^a']);
    });
  });
}

class _OtherPattern implements Pattern {
  @override
  Iterable<Match> allMatches(String string, [int start = 0]) => const <Match>[];

  @override
  Match? matchAsPrefix(String string, [int start = 0]) => null;
}
