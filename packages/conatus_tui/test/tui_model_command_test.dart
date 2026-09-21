/// `/model` 命令与 [ConatusTuiController.rebind]：运行时换模型。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_tui/conatus_tui.dart';
import 'package:test/test.dart';

/// 固定回复的假 provider。
class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this._reply);

  final String _reply;

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async =>
      LlmResult(content: _reply, provider: 'scripted', model: 'm');

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

Future<(ConatusTuiController, Context, Disposer)> _build(String reply) async {
  final Context app = Context.root();
  provideTools(app);
  final Disposer llm = provideLlm(
    app,
    llm: FallbackLlm(<LlmProvider>[_ScriptedProvider(reply)]),
  );
  provideMemory(app);
  final SessionStore sessions = provideSessions(app);
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    initialSession: 's1',
    modelLabel: 'scripted',
    onExit: () {},
  );
  await controller.start();
  return (controller, app, llm);
}

void main() {
  test('/model 未注入钩子时提示未装配', () async {
    final (ConatusTuiController controller, Context app, Disposer _) =
        await _build('回复');

    await controller.handleLine('/model');

    expect(controller.transcript.messages.single.role, TuiRole.system);
    expect(controller.transcript.messages.single.text, contains('未装配'));
    app.dispose();
  });

  test('/model 转发参数并显示钩子返回的提示', () async {
    final (ConatusTuiController controller, Context app, Disposer _) =
        await _build('回复');
    final List<String> calls = <String>[];
    controller.onModelCommand = (String arg) async {
      calls.add(arg);
      return '已切换：$arg';
    };

    await controller.handleLine('/model deepseek-chat');

    expect(calls, <String>['deepseek-chat']);
    expect(controller.transcript.messages.last.text, '已切换：deepseek-chat');
    app.dispose();
  });

  test('rebind 后新一轮用替换后的提供商，历史保留', () async {
    final (ConatusTuiController controller, Context app, Disposer initial) =
        await _build('旧回复');
    await controller.handleLine('在吗');
    expect(controller.transcript.messages.last.text, '旧回复');

    initial();
    provideLlm(app, llm: FallbackLlm(<LlmProvider>[_ScriptedProvider('新回复')]));
    controller.modelLabel = 'new';
    expect(await controller.rebind(), isTrue);

    await controller.handleLine('在吗');

    expect(controller.transcript.messages.last.text, '新回复');
    expect(controller.modelLabel, 'new');
    expect(
      controller.transcript.messages
          .where((TuiMessage m) => m.role == TuiRole.user),
      hasLength(2),
    );
    app.dispose();
  });
}
