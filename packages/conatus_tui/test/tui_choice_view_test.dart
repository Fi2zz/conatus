/// 选项浮层的渲染与按键：↑↓ 移动、Enter 确认、Esc 取消。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_tui/conatus_tui.dart';
import 'package:nocterm/nocterm.dart';
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

void main() {
  test('浮层渲染标题、选项说明与当前标记', () async {
    final Context app = Context.root();
    provideTools(app);
    provideLlm(app, llm: FallbackLlm(<LlmProvider>[_NoopProvider()]));
    final SessionStore sessions = provideSessions(app);
    final ConatusTuiController controller = ConatusTuiController(
      app: app,
      sessions: sessions,
      name: '测试',
      initialSession: 'choice',
      modelLabel: 'mock',
      onExit: () {},
    );

    final NoctermTester tester = await NoctermTester.create();
    try {
      await tester.pumpComponent(AgentTui(controller: controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final Future<String?> pending = controller.choice.ask(const TuiChoiceRequest(
        title: '用什么权限模式？',
        choices: <TuiChoice>[
          TuiChoice(id: 'a', label: '始终询问', description: '只读自动放行。'),
          TuiChoice(id: 'b', label: '按需询问', description: '高危仍询问。', current: true),
        ],
      ));
      await tester.pump();

      expect(tester.terminalState, containsText('用什么权限模式？'));
      expect(tester.terminalState, containsText('始终询问'));
      expect(tester.terminalState, containsText('只读自动放行。'));
      expect(tester.terminalState, containsText('当前'));
      expect(tester.terminalState, containsText('选择'));

      controller.choice.cancel();
      await pending;
      await tester.pump();

      expect(
        tester.terminalState,
        isNot(containsText('用什么权限模式？')),
      );
    } finally {
      tester.dispose();
      app.dispose();
    }
  });

  test('状态栏展示当前权限模式', () async {
    final Context app = Context.root();
    provideTools(app);
    provideLlm(app, llm: FallbackLlm(<LlmProvider>[_NoopProvider()]));
    final SessionStore sessions = provideSessions(app);
    final ConatusTuiController controller = ConatusTuiController(
      app: app,
      sessions: sessions,
      name: '测试',
      initialSession: 'perm',
      modelLabel: 'mock',
      onExit: () {},
    );

    final NoctermTester tester = await NoctermTester.create();
    try {
      await tester.pumpComponent(AgentTui(controller: controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.terminalState, containsText('权限：按需询问'));

      controller.applyPermissionMode(TuiPermissionMode.alwaysAsk);
      await tester.pump();

      expect(tester.terminalState, containsText('权限：始终询问'));
    } finally {
      tester.dispose();
      app.dispose();
    }
  });
}
