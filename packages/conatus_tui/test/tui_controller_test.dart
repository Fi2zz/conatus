/// 控制器：把 Agent Loop 的事件投射到屏上记录，并处理斜杠命令。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_tui/conatus_tui.dart';
import 'package:test/test.dart';

/// 按脚本返回结果的假 provider。
class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this._replies);

  final List<LlmResult> _replies;
  int _index = 0;

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async =>
      _replies[_index++];

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

Future<(ConatusTuiController, Context)> _build(List<LlmResult> replies) async {
  final Context app = Context.root();
  provideTools(app);
  app.effect(() => app.tools.fn(
        'get_time',
        description: '返回时间',
        handler: (ToolContext ctx) async => ToolResult.success('12:00'),
      ));
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[_ScriptedProvider(replies)]));
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
  return (controller, app);
}

void main() {
  test('纯文本回复写入 user + assistant', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      <LlmResult>[
        const LlmResult(content: '你好呀', provider: 'scripted', model: 'm'),
      ],
    );

    await controller.handleLine('在吗');

    final List<TuiRole> roles =
        controller.transcript.messages.map((TuiMessage m) => m.role).toList();
    expect(roles, <TuiRole>[TuiRole.user, TuiRole.assistant]);
    expect(controller.transcript.messages.last.text, '你好呀');
    app.dispose();
  });

  test('工具调用轮：回显工具调用与结果，再收口', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      <LlmResult>[
        const LlmResult(
          content: '',
          provider: 'scripted',
          model: 'm',
          toolCalls: <LlmToolCall>[
            LlmToolCall(id: '1', name: 'get_time'),
          ],
        ),
        const LlmResult(
            content: '现在是 12:00。', provider: 'scripted', model: 'm'),
      ],
    );

    await controller.handleLine('几点？');

    final List<TuiRole> roles =
        controller.transcript.messages.map((TuiMessage m) => m.role).toList();
    expect(
      roles,
      <TuiRole>[TuiRole.user, TuiRole.stage, TuiRole.tool, TuiRole.assistant],
    );
    expect(
      controller.transcript.messages
          .firstWhere((TuiMessage m) => m.role == TuiRole.stage)
          .text,
      contains('get_time'),
    );
    expect(
      controller.transcript.messages
          .firstWhere((TuiMessage m) => m.role == TuiRole.tool)
          .text,
      contains('✓'),
    );
    expect(controller.transcript.messages.last.text, '现在是 12:00。');
    app.dispose();
  });

  test('未知命令给出提示，不进入对话链路', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
    );

    await controller.handleLine('/nope');

    expect(controller.transcript.messages.single.role, TuiRole.system);
    expect(controller.transcript.messages.single.text, contains('未知命令'));
    app.dispose();
  });

  test('/tools 列出已注册工具', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
    );

    await controller.handleLine('/tools');

    expect(controller.transcript.messages.single.text, contains('get_time'));
    app.dispose();
  });

  test('切换会话：id 变化并写入提示', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
    );

    await controller.handleLine('/session work');

    expect(controller.sessionId, 'work');
    expect(
      controller.transcript.messages.last.text,
      contains('已切换到会话 work'),
    );
    app.dispose();
  });

  test('会话 id 校验', () {
    expect(isValidSessionId('work_1'), isTrue);
    expect(isValidSessionId('会话-一'), isTrue);
    expect(isValidSessionId('a b'), isFalse);
    expect(isValidSessionId(''), isFalse);
    expect(isValidSessionId('x' * 65), isFalse);
  });
}
