/// 根组件的渲染冒烟测试（nocterm 测试框架）。
library;

import 'dart:async';
import 'dart:io';

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

/// chat 永远挂起、不返回的 provider，用于制造稳定的"在飞轮次"。
class _HangingProvider implements LlmProvider {
  @override
  String get name => 'hang';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      Completer<LlmResult>().future;

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

  test('输入框非空时 Ctrl+C 清空输入框', () async {
    final (ConatusTuiController controller, NoctermTester tester, Context app) =
        await _launchAgentTui();
    try {
      await tester.enterText('hello');
      await tester.pump();
      expect(tester.terminalState, containsText('hello'));

      // Ctrl+C：清空输入框，不触发退出确认。
      await tester.sendKeyEvent(const KeyboardEvent(
        logicalKey: LogicalKey.keyC,
        modifiers: ModifierKeys(ctrl: true),
      ));
      await tester.pump();
      expect(tester.terminalState, isNot(containsText('hello')));
      expect(tester.terminalState, isNot(containsText('再按一次 Ctrl+C 退出')));
    } finally {
      tester.dispose();
      controller.dispose();
      app.dispose();
    }
  });

  test('选中消息文本后复制并清除选区（macOS Alt+C，其他平台 Ctrl+C）', () async {
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

      // 复制键：macOS 为 Alt+C，其他平台为 Ctrl+C。复制后不触发退出确认。
      await tester.sendKeyEvent(KeyboardEvent(
        logicalKey: LogicalKey.keyC,
        modifiers: Platform.isMacOS
            ? const ModifierKeys(alt: true)
            : const ModifierKeys(ctrl: true),
      ));
      expect(ClipboardManager.paste(), 'copy me');
      expect(tester.terminalState, isNot(containsText('再按一次 Ctrl+C 退出')));

      // 选区已清除：再按 Ctrl+C 恢复退出确认（两平台空闲时一致）。
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

  test('忙时 Esc 打断并提示', () async {
    final (ConatusTuiController controller, NoctermTester tester, Context app) =
        await _launchAgentTui(provider: _HangingProvider());
    try {
      // 提交一轮挂起对话，制造稳定的在飞轮次。
      unawaited(controller.submit('你好'));
      await tester.pump();
      expect(controller.busy, isTrue);

      // Esc 打断：立即提示，不进入退出确认。
      await tester.sendEscape();
      await tester.pump();
      expect(tester.terminalState, containsText('正在打断…'));
      expect(tester.terminalState, isNot(containsText('再按一次 Ctrl+C 退出')));
    } finally {
      tester.dispose();
      controller.dispose();
      app.dispose();
    }
  });

  test('忙时 Ctrl+C 打断而不进入退出确认（macOS）', () async {
    final (ConatusTuiController controller, NoctermTester tester, Context app) =
        await _launchAgentTui(provider: _HangingProvider());
    try {
      unawaited(controller.submit('你好'));
      await tester.pump();
      expect(controller.busy, isTrue);

      // macOS：忙时 Ctrl+C 直接打断；其他平台 Ctrl+C 无选区走退出确认。
      await tester.sendKeyEvent(const KeyboardEvent(
        logicalKey: LogicalKey.keyC,
        modifiers: ModifierKeys(ctrl: true),
      ));
      await tester.pump();
      if (Platform.isMacOS) {
        expect(
          tester.terminalState,
          isNot(containsText('再按一次 Ctrl+C 退出')),
        );
      } else {
        expect(tester.terminalState, containsText('再按一次 Ctrl+C 退出'));
      }
    } finally {
      tester.dispose();
      controller.dispose();
      app.dispose();
    }
  });

  test('空闲时 Esc 打断提示没有进行中的对话', () async {
    final (ConatusTuiController controller, NoctermTester tester, Context app) =
        await _launchAgentTui();
    try {
      // 无面板、无视图、无在飞轮次：Esc 落到打断兜底并提示。
      await tester.sendEscape();
      await tester.pump();
      expect(tester.terminalState, containsText('当前没有进行中的对话。'));
    } finally {
      tester.dispose();
      controller.dispose();
      app.dispose();
    }
  });

  test('/help 弹出可用 Esc 关闭', () async {
    final (ConatusTuiController controller, NoctermTester tester, Context app) =
        await _launchAgentTui();
    try {
      // 输入 /help 并提交，帮助文本弹出（自动滚动到可见区域，断言底部按键行）。
      await tester.enterText('/help');
      await tester.sendEnter();
      await tester.pump();
      expect(tester.terminalState, containsText('按键：Esc 关闭面板/视图'));

      // Esc 关闭帮助弹出。
      await tester.sendEscape();
      await tester.pump();
      expect(tester.terminalState, isNot(containsText('按键：Esc 关闭面板/视图')));
      expect(tester.terminalState, containsText('输入文字开始对话'));
    } finally {
      tester.dispose();
      controller.dispose();
      app.dispose();
    }
  });
}

/// 装配一个最小 TUI 并挂载，返回（控制器, 测试器, 应用上下文）。
Future<(ConatusTuiController, NoctermTester, Context)> _launchAgentTui({
  LlmProvider? provider,
}) async {
  final Context app = Context.root();
  provideTools(app);
  provideLlm(
    app,
    llm: FallbackLlm(<LlmProvider>[provider ?? _NoopProvider()]),
  );
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
