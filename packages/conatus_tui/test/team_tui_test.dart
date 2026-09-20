/// 团队 UI 集成测试：装配真实团队后，状态栏随事件出现、Ctrl+T 切换视图。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_team/conatus_team.dart';
import 'package:conatus_tui/conatus_tui.dart';
import 'package:test/test.dart';

/// 从不被调用的占位 provider（spawn 只建成员运行时，不触发模型调用）。
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

Future<void> _flush() async {
  for (int i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('团队事件驱动状态栏出现；Ctrl+T 切换对话/团队视图', () async {
    final Context app = Context.root();
    provideTools(app);
    provideLlm(app, llm: FallbackLlm(<LlmProvider>[_NoopProvider()]));
    final SessionStore sessions = provideSessions(app);
    final ConatusTuiController controller = ConatusTuiController(
      app: app,
      sessions: sessions,
      name: '测试',
      initialSession: 'team',
      modelLabel: 'mock',
      onExit: () {},
    );
    AgentTeam? team;
    controller.configureSession = (Context ctx, Session session) {
      team = ctx.get<AgentTeam>('team');
    };

    final NoctermTester tester = await NoctermTester.create();
    try {
      await tester.pumpComponent(AgentTui(controller: controller));
      await tester.pump();
      await _flush();
      await tester.pump();

      // 空团队：状态栏不渲染。
      expect(tester.terminalState, isNot(containsText('团队:')));

      // 创建成员：状态栏出现团队概况。
      final AgentTeam bound = team!;
      await bound.spawn(name: 'reviewer');
      await _flush();
      await tester.pump();
      expect(tester.terminalState, containsText('团队: 1 成员'));
      expect(tester.terminalState, containsText('任务: 0/0 完成'));

      // Ctrl+T：切到团队视图。
      await tester.sendKeyEvent(const KeyboardEvent(
        logicalKey: LogicalKey.keyT,
        modifiers: ModifierKeys(ctrl: true),
      ));
      await tester.pump();
      expect(tester.terminalState, containsText('团队视图'));
      expect(tester.terminalState, containsText('reviewer'));

      // 再按 Ctrl+T：返回对话视图。
      await tester.sendKeyEvent(const KeyboardEvent(
        logicalKey: LogicalKey.keyT,
        modifiers: ModifierKeys(ctrl: true),
      ));
      await tester.pump();
      expect(tester.terminalState, isNot(containsText('团队视图')));
    } finally {
      tester.dispose();
      controller.dispose();
      app.dispose();
    }
  });
}
