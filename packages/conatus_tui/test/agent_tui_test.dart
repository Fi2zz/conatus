/// 根组件的渲染冒烟测试（nocterm 测试框架）。
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
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

void main() {
  test('AgentTui 渲染顶栏与空态提示', () async {
    final Context app = Context.root();
    provideTools(app);
    provideLlm(app, llm: FallbackLlm(<LlmProvider>[_NoopProvider()]));
    final SessionStore sessions = provideSessions(app);
    final ConatusTuiController controller = ConatusTuiController(
      app: app,
      sessions: sessions,
      name: '测试',
      initialSession: 'smoke',
      modelLabel: 'mock',
      onExit: () {},
    );

    final NoctermTester tester = await NoctermTester.create();
    try {
      await tester.pumpComponent(AgentTui(controller: controller));
      // 光标闪烁等持续动画会让 pumpAndSettle 无法收敛，故只按帧推进。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.terminalState, containsText('conatus TUI'));
      expect(tester.terminalState, containsText('会话：smoke'));
      expect(tester.terminalState, containsText('输入文字开始对话'));
    } finally {
      tester.dispose();
      app.dispose();
    }
  });
}
