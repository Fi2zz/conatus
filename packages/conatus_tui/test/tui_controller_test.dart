/// 控制器：把 Agent Loop 的事件投射到屏上记录，并处理斜杠命令。
library;

import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_tui/conatus_tui.dart';
import 'package:test/test.dart';

/// 模型调用挂起不返回，直到被放行（模拟对端不响应）。
class _HangingProvider implements LlmProvider {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  String get name => 'hanging';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    return const LlmResult(content: '迟到', provider: 'hanging', model: 'm');
  }

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
    List<Map<String, dynamic>>? tools,
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

  test('/plan 切换 Plan Mode 并给出提示', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
    );

    await controller.handleLine('/plan');
    expect(controller.transcript.messages.last.text, contains('已进入 Plan Mode'));
    expect(
        controller.transcript.messages.last.text, contains('exit_plan_mode'));

    await controller.handleLine('/plan');
    expect(controller.transcript.messages.last.text, contains('已退出 Plan Mode'));
    app.dispose();
  });

  test('Plan Mode 激活时拦截 medium 工具，退出后放行', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
    );
    app.effect(() => app.tools.fn(
          'danger',
          description: '有副作用的操作',
          riskLevel: ToolRisk.medium,
          handler: (ToolContext ctx) async => ToolResult.success('done'),
        ));
    Future<ToolResult> callDanger() =>
        app.tools.call(const ToolCall(name: 'danger'));

    expect((await callDanger()).isError, isFalse);

    await controller.handleLine('/plan');
    final ToolResult blocked = await callDanger();
    expect(blocked.isError, isTrue);
    expect(blocked.error!.code, 'PLAN_MODE_BLOCKED');

    await controller.handleLine('/plan');
    expect((await callDanger()).isError, isFalse);
    app.dispose();
  });

  test('exit_plan_mode 随会话绑定注册，切换会话后保持可用', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
    );

    expect(app.tools.get(kExitPlanModeToolName), isNotNull);

    await controller.handleLine('/session work');

    expect(app.tools.get(kExitPlanModeToolName), isNotNull);
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

  test('/remember 直接记住，不经模型', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
    );
    final MemoryStore memory = app.require<MemoryStore>('memory');

    await controller.handleLine('/remember 用户喜欢京剧');

    expect(controller.transcript.messages.single.text, contains('已记住'));
    expect(memory.entries.single.text, '用户喜欢京剧');
    app.dispose();
  });

  test('/forget 直接遗忘，不经模型', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
    );
    final MemoryStore memory = app.require<MemoryStore>('memory');
    await memory.remember('用户喜欢京剧');

    await controller.handleLine('/forget 京剧');

    expect(controller.transcript.messages.single.text, contains('已遗忘'));
    expect(memory.length, 0);
    app.dispose();
  });

  test('interrupt 打断在飞轮次：busy 复位且不产回复', () async {
    final _HangingProvider provider = _HangingProvider();
    final Context app = Context.root();
    provideTools(app);
    provideLlm(app, llm: FallbackLlm(<LlmProvider>[provider]));
    final SessionStore sessions = provideSessions(app);
    final ConatusTuiController controller = ConatusTuiController(
      app: app,
      sessions: sessions,
      name: 'test',
      initialSession: 's1',
      modelLabel: 'hanging',
      onExit: () {},
    );
    await controller.start();

    final Future<void> running = controller.handleLine('你好');
    await provider.started.future;
    expect(controller.busy, isTrue);

    controller.interrupt();
    await running;

    expect(controller.busy, isFalse);
    expect(
      controller.transcript.messages.any(
        (TuiMessage m) => m.role == TuiRole.assistant,
      ),
      isFalse,
    );
    expect(controller.transcript.messages.last.text, contains('已打断'));
    provider.release.complete();
    app.dispose();
  });
}
