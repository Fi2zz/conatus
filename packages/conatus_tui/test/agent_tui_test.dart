/// 根组件的渲染冒烟测试（nocterm 测试框架）。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
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

      expect(tester.terminalState, containsText('Conatus TUI'));
      expect(tester.terminalState, containsText('会话：smoke'));
      expect(tester.terminalState, containsText('输入文字开始对话'));
    } finally {
      tester.dispose();
      app.dispose();
    }
  });

  test('Esc 关闭团队视图返回对话', () async {
    final (ConatusTuiController controller, NoctermTester tester, Context app) =
        await _launchAgentTui();
    try {
      // Ctrl+T 进入团队视图。
      await tester.sendKeyEvent(const KeyboardEvent(
        logicalKey: LogicalKey.keyT,
        modifiers: ModifierKeys(ctrl: true),
      ));
      expect(tester.terminalState, containsText('团队视图'));

      // Esc 返回对话视图。
      await tester.sendEscape();
      expect(tester.terminalState, isNot(containsText('团队视图')));
      expect(tester.terminalState, containsText('输入文字开始对话'));
    } finally {
      tester.dispose();
      controller.dispose();
      app.dispose();
    }
  });

  test('Ctrl+C 无选区时仍走退出确认', () async {
    final (ConatusTuiController controller, NoctermTester tester, Context app) =
        await _launchAgentTui();
    try {
      await tester.sendKeyEvent(const KeyboardEvent(
        logicalKey: LogicalKey.keyC,
        modifiers: ModifierKeys(ctrl: true),
      ));
      expect(tester.terminalState, containsText('再按一次 Ctrl+C 退出'));
    } finally {
      tester.dispose();
      controller.dispose();
      app.dispose();
    }
  });

  test('选中消息文本后 Ctrl+C 复制并清除选区', () async {
    final (ConatusTuiController controller, NoctermTester tester, Context app) =
        await _launchAgentTui();
    try {
      ClipboardManager.clear();

      // 注入一条消息并刷新（system 角色无全角 label，避免 buffer 与渲染列偏移）。
      controller.transcript.add(TuiRole.system, 'copy me');
      controller.onChanged?.call();
      await tester.pump();
      expect(tester.terminalState, containsText('copy me'));

      // 鼠标拖选该消息文本。
      final TextMatch match = tester.terminalState.findText('copy me').first;
      await tester.mouseMove(match.x, match.y, match.x + 7, match.y);
      await tester.release(match.x + 7, match.y);

      // Ctrl+C：复制到剪贴板，不触发退出确认。
      await tester.sendKeyEvent(const KeyboardEvent(
        logicalKey: LogicalKey.keyC,
        modifiers: ModifierKeys(ctrl: true),
      ));
      expect(ClipboardManager.paste(), 'copy me');
      expect(tester.terminalState, isNot(containsText('再按一次 Ctrl+C 退出')));

      // 选区已清除：再按 Ctrl+C 恢复退出确认。
      await tester.sendKeyEvent(const KeyboardEvent(
        logicalKey: LogicalKey.keyC,
        modifiers: ModifierKeys(ctrl: true),
      ));
      expect(tester.terminalState, containsText('再按一次 Ctrl+C 退出'));
    } finally {
      tester.dispose();
      controller.dispose();
      app.dispose();
    }
  });
}

/// 装配一个最小 TUI 并挂载，返回（控制器, 测试器, 应用上下文）。
Future<(ConatusTuiController, NoctermTester, Context)> _launchAgentTui() async {
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
  await tester.pumpComponent(AgentTui(controller: controller));
  await tester.pump();
  return (controller, tester, app);
}
