import 'dart:convert';
import 'dart:io';

import 'package:conatus_intent/conatus_intent.dart';
import 'package:test/test.dart';

const Map<String, Object?> _config = <String, Object?>{
  'intents': <Object?>[
    <String, Object?>{
      'name': 'light_on',
      'description': '开灯',
      'patterns': <Object?>['^(开灯|把灯打开)'],
      'examples': <Object?>['亮一点'],
      'priority': 10,
      'action': <String, Object?>{
        'type': 'tool',
        'tool': 'device_control',
        'args': <String, Object?>{'device': 'light', 'op': 'on'},
      },
    },
    <String, Object?>{
      'name': 'morning_routine',
      'description': '晨间例行',
      'patterns': <Object?>['^(早上好|晨间播报)'],
      'action': <String, Object?>{'type': 'builtin', 'handler': 'morning'},
    },
    <String, Object?>{
      'name': 'code_review',
      'description': '代码审查',
      'patterns': <Object?>['^(审查代码|review code)'],
      'action': <String, Object?>{'type': 'delegate', 'skill': 'code-review'},
    },
    <String, Object?>{
      'name': 'greeting',
      'description': '问候',
      'patterns': <Object?>['^(你好|hi|hello)'],
      'action': <String, Object?>{'type': 'respond', 'text': '你好，有什么可以帮你？'},
    },
  ],
};

IntentLoader _loader(DefaultIntentRouter router) => IntentLoader(
      router: router,
      handlers: <String, IntentHandler>{
        'morning': (RouteContext ctx) async => '已播报',
      },
    );

void main() {
  late DefaultIntentRouter router;
  late IntentLoader loader;

  setUp(() {
    router = DefaultIntentRouter();
    loader = _loader(router);
  });

  tearDown(() => router.dispose());

  test('解析四种动作类型', () {
    final List<Map<String, Object?>> items = <Map<String, Object?>>[
      for (final Object? item in _config['intents'] as List)
        Map<String, Object?>.from(item as Map),
    ];

    final Intent tool = loader.parse(items[0]);
    final Intent builtin = loader.parse(items[1]);
    final Intent delegate = loader.parse(items[2]);
    final Intent respond = loader.parse(items[3]);

    expect(tool.action, isA<ToolAction>());
    expect((tool.action as ToolAction).tool, 'device_control');
    expect(tool.patterns, hasLength(1));
    expect(tool.priority, 10);
    expect(builtin.action, isA<DirectAction>());
    expect(delegate.action, isA<DelegateAction>());
    expect((delegate.action as DelegateAction).skill, 'code-review');
    expect(respond.action, isA<DirectAction>());
  });

  test('动作 JSON 往返一致', () {
    final Intent original = loader.parse(<String, Object?>{
      'name': 'light_on',
      'description': '开灯',
      'action': <String, Object?>{
        'type': 'tool',
        'tool': 'device_control',
        'args': <String, Object?>{'device': 'light'},
      },
    });

    final RoutedAction rebuilt = loader.buildAction(original.action.toJson());

    expect(rebuilt, isA<ToolAction>());
    expect((rebuilt as ToolAction).tool, 'device_control');
    expect(rebuilt.argsTemplate, <String, Object?>{'device': 'light'});
  });

  test('respond 与 delegate 动作也能往返', () {
    const DirectAction respond = DirectAction.respond('你好');
    const DelegateAction delegate = DelegateAction(skill: 'code-review');

    expect(loader.buildAction(respond.toJson()), isA<DirectAction>());
    expect(
      (loader.buildAction(delegate.toJson()) as DelegateAction).skill,
      'code-review',
    );
  });

  test('未知动作类型抛 unknown-action', () {
    expect(
      () => loader.buildAction(<String, Object?>{'type': 'magic'}),
      throwsA(
        isA<IntentException>()
            .having((IntentException e) => e.code, 'code', 'unknown-action'),
      ),
    );
  });

  test('未注册的内置处理器抛 unknown-handler', () {
    expect(
      () => loader.buildAction(
        <String, Object?>{'type': 'builtin', 'handler': 'nope'},
      ),
      throwsA(
        isA<IntentException>()
            .having((IntentException e) => e.code, 'code', 'unknown-handler'),
      ),
    );
  });

  test('缺少必填字段抛 missing-field', () {
    expect(
      () => loader.buildAction(<String, Object?>{'type': 'respond'}),
      throwsA(
        isA<IntentException>()
            .having((IntentException e) => e.code, 'code', 'missing-field'),
      ),
    );
    expect(
      () => loader.parse(<String, Object?>{'description': '没有名字'}),
      throwsA(
        isA<IntentException>()
            .having((IntentException e) => e.code, 'code', 'missing-field'),
      ),
    );
  });

  test('loadFromJson 逐个注册并可路由', () async {
    await loader.loadFromJson(_config);

    expect(
      router.intents.map((Intent i) => i.name),
      <String>['light_on', 'morning_routine', 'code_review', 'greeting'],
    );

    final RouteResult hit = await router.route('你好');
    expect(hit.intent!.name, 'greeting');

    final RouteResult tool = await router.route('开灯');
    final ToolAction action = tool.intent!.action as ToolAction;
    expect(
      action.resolveArgs(const RouteContext(input: '开灯')),
      <String, Object?>{'device': 'light', 'op': 'on'},
    );
  });

  test('intents 不是数组时抛 bad-type', () {
    expect(
      () => loader.loadFromJson(<String, Object?>{'intents': 'nope'}),
      throwsA(
        isA<IntentException>()
            .having((IntentException e) => e.code, 'code', 'bad-type'),
      ),
    );
  });

  test('loadFromFile 从磁盘加载', () async {
    final Directory dir = Directory.systemTemp.createTempSync('intent-loader');
    addTearDown(() => dir.deleteSync(recursive: true));
    final File file = File('${dir.path}/intents.json')
      ..writeAsStringSync(_encode(_config));

    await loader.loadFromFile(file);

    expect(router.intents, hasLength(4));
  });
}

String _encode(Map<String, Object?> json) => jsonEncode(json);
