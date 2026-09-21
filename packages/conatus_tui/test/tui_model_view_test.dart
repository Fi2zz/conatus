/// 模型选择浮层的渲染与过滤。
library;

import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_providers/conatus_providers.dart';
import 'package:conatus_tui/conatus_tui.dart';
import 'package:test/test.dart';

/// 从不被调用的占位 provider。
class _NoopProvider implements LlmProvider {
  @override
  String get name => 'noop';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      throw UnimplementedError();

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

Future<(ConatusTuiController, Context, Directory)> _controller({
  bool withProviders = false,
}) async {
  final Directory dir = Directory.systemTemp.createTempSync('model-view-');
  final Context app = Context.root();
  provideTools(app);
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[_NoopProvider()]));
  if (withProviders) {
    final ProviderRegistry registry = provideProviders(
      app,
      store: ProviderStore(path: '${dir.path}/providers.json'),
      builtin: <ProviderProfile>[
        const ProviderProfile(
          name: 'ark',
          baseUrl: 'https://ark.example/v1',
          models: <String>['a-small', 'a-large'],
        ),
        const ProviderProfile(
          name: 'deepseek',
          baseUrl: 'https://deepseek.example/v1',
          models: <String>['b-small'],
        ),
      ],
    );
    await registry.load();
  }
  final SessionStore sessions = provideSessions(app);
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: '测试',
    initialSession: 'model',
    modelLabel: 'a-small',
    onExit: () {},
  );
  return (controller, app, dir);
}

const List<TuiModelItem> _items = <TuiModelItem>[
  TuiModelItem(provider: 'ark', model: 'a-small', current: true),
  TuiModelItem(provider: 'ark', model: 'a-large'),
  TuiModelItem(provider: 'deepseek', model: 'b-small'),
];

void main() {
  test('渲染标题、提供商标签、模型行与当前标记', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _controller();
    final NoctermTester tester = await NoctermTester.create();
    try {
      await tester.pumpComponent(AgentTui(controller: controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      controller.modelPrompt.show(_items);
      await tester.pump();

      expect(tester.terminalState, containsText('Select a model'));
      expect(tester.terminalState, containsText('Tab 切换提供商'));
      expect(tester.terminalState, containsText('[All]'));
      expect(tester.terminalState, containsText('a-small'));
      expect(tester.terminalState, containsText('b-small'));
      expect(tester.terminalState, containsText('当前'));
      expect(tester.terminalState, containsText('输入过滤模型名'));
    } finally {
      tester.dispose();
      app.dispose();
      dir.deleteSync(recursive: true);
    }
  });

  test('搜索词与提供商过滤改变可见行', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _controller();
    final NoctermTester tester = await NoctermTester.create();
    try {
      await tester.pumpComponent(AgentTui(controller: controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      controller.modelPrompt.show(_items);
      await tester.pump();

      controller.modelPrompt.setQuery('b-');
      await tester.pump();
      expect(tester.terminalState, containsText('b-small'));
      expect(tester.terminalState, isNot(containsText('a-large')));

      controller.modelPrompt.setQuery('');
      controller.modelPrompt.toggleProvider();
      await tester.pump();
      expect(tester.terminalState, containsText('[ark]'));
      expect(tester.terminalState, isNot(containsText('b-small')));

      controller.modelPrompt.close();
      await tester.pump();
      expect(tester.terminalState, isNot(containsText('Select a model')));
    } finally {
      tester.dispose();
      app.dispose();
      dir.deleteSync(recursive: true);
    }
  });

  test('按键到达浮层：↑↓ 移动、Enter 确认、Esc 取消', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _controller();
    final NoctermTester tester =
        await NoctermTester.create(size: const Size(80, 40));
    try {
      await tester.pumpComponent(AgentTui(controller: controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      controller.modelPrompt.show(_items);
      await tester.pump();

      await tester.sendArrowDown();
      expect(controller.modelPrompt.index, 1);

      await tester.sendEscape();
      expect(controller.modelPrompt.open, isFalse);
    } finally {
      tester.dispose();
      app.dispose();
      dir.deleteSync(recursive: true);
    }
  });

  test('Enter 确认切换模型（完整路径）', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _controller(withProviders: true);
    final List<String> swapped = <String>[];
    controller.switchLlm =
        (FallbackLlm llm) => swapped.add(llm.providers.first.name);
    final NoctermTester tester =
        await NoctermTester.create(size: const Size(80, 40));
    try {
      await tester.pumpComponent(AgentTui(controller: controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await controller.handleLine('/model');
      await tester.pump();
      expect(controller.modelPrompt.open, isTrue);

      await tester.sendArrowDown();
      await tester.sendEnter();
      await tester.pump();

      expect(controller.modelPrompt.open, isFalse);
      expect(swapped, <String>['ark']);
      expect(controller.modelLabel, 'a-large');
    } finally {
      tester.dispose();
      app.dispose();
      dir.deleteSync(recursive: true);
    }
  });

  test('字符输入进入搜索框并过滤', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _controller();
    final NoctermTester tester =
        await NoctermTester.create(size: const Size(80, 40));
    try {
      await tester.pumpComponent(AgentTui(controller: controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      controller.modelPrompt.show(_items);
      await tester.pump();

      await tester.sendKeyEvent(const KeyboardEvent(
        logicalKey: LogicalKey.keyB,
        character: 'b',
      ));
      await tester.pump();

      expect(controller.modelPrompt.search.text, 'b');
      expect(controller.modelPrompt.query, 'b');
    } finally {
      tester.dispose();
      app.dispose();
      dir.deleteSync(recursive: true);
    }
  });

  test('连续字符输入：重建后仍保持焦点', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _controller();
    final NoctermTester tester =
        await NoctermTester.create(size: const Size(80, 40));
    try {
      await tester.pumpComponent(AgentTui(controller: controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      controller.modelPrompt.show(_items);
      await tester.pump();

      for (final String ch in <String>['l', 'a', 'r']) {
        await tester.sendKeyEvent(KeyboardEvent(
          logicalKey: LogicalKey.keyA,
          character: ch,
        ));
        await tester.pump();
      }

      expect(controller.modelPrompt.search.text, 'lar');
      expect(controller.modelPrompt.query, 'lar');
    } finally {
      tester.dispose();
      app.dispose();
      dir.deleteSync(recursive: true);
    }
  });

  test('超过可见行数时给出折叠提示', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _controller();
    final NoctermTester tester =
        await NoctermTester.create(size: const Size(80, 40));
    try {
      await tester.pumpComponent(AgentTui(controller: controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      controller.modelPrompt.show(<TuiModelItem>[
        for (int i = 0; i < kTuiModelVisible + 4; i++)
          TuiModelItem(provider: 'ark', model: 'm$i'),
      ]);
      await tester.pump();

      expect(tester.terminalState, containsText('还有 4 个'));
    } finally {
      tester.dispose();
      app.dispose();
      dir.deleteSync(recursive: true);
    }
  });
}
