import 'dart:convert';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_intent/conatus_intent.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

/// 记录请求次数的模型；永远返回同一段文本。
class _CountingLlm implements LlmProvider {
  int calls = 0;

  @override
  String get name => 'counting';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls++;
    return const LlmResult(content: '模型收口', provider: 'counting', model: 'm');
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

void main() {
  test('provideIntentRouter 提供服务并接线快路径', () {
    final Context app = Context.root();
    addTearDown(app.dispose);

    final IntentRouter router = provideIntentRouter(app);

    expect(app.intentRouter, same(router));
    expect(app.get<Router>('router'), isA<IntentRouterAdapter>());
  });

  test('fastPath: false 时只提供服务', () {
    final Context app = Context.root();
    addTearDown(app.dispose);

    provideIntentRouter(app, fastPath: false);

    expect(app.get<Router>('router'), isNull);
  });

  test('intents 参数在装配时注册', () {
    final Context app = Context.root();
    addTearDown(app.dispose);

    provideIntentRouter(
      app,
      intents: <Intent>[
        Intent(
          name: 'ping',
          description: 'ping',
          patterns: <Pattern>[RegExp('^ping')],
          action: const DirectAction.respond('pong'),
        ),
      ],
    );

    expect(app.intentRouter.intents, hasLength(1));
  });

  group('IntentRouterAdapter', () {
    late DefaultIntentRouter router;
    late IntentRouterAdapter adapter;

    setUp(() {
      router = DefaultIntentRouter();
      adapter = IntentRouterAdapter(router);
    });

    tearDown(() => router.dispose());

    test('直接动作 → RouteReply', () async {
      router.register(Intent(
        name: 'greeting',
        description: '',
        patterns: <Pattern>[RegExp('^你好')],
        action: const DirectAction.respond('你好，有什么可以帮你？'),
      ));

      final RouteDecision decision = await adapter.route('你好');

      expect(decision, isA<RouteReply>());
      expect((decision as RouteReply).text, '你好，有什么可以帮你？');
    });

    test('工具动作 → RouteTools', () async {
      router.register(Intent(
        name: 'weather',
        description: '',
        patterns: <Pattern>[RegExp('^查天气')],
        action: const ToolAction(
          tool: 'web_search',
          argsTemplate: <String, Object?>{'query': '{{input}}'},
        ),
      ));

      final RouteDecision decision = await adapter.route('查天气');

      expect(decision, isA<RouteTools>());
      final LlmToolCall call = (decision as RouteTools).calls.single;
      expect(call.name, 'web_search');
      expect(call.id, 'intent:weather');
      expect(
        jsonDecode(call.arguments),
        <String, Object?>{'query': '查天气'},
      );
    });

    test('委托动作 → 预置 skill 工具调用', () async {
      router.register(Intent(
        name: 'code_review',
        description: '',
        patterns: <Pattern>[RegExp('^审查代码')],
        action: const DelegateAction(skill: 'code-review'),
      ));

      final RouteDecision decision = await adapter.route('审查代码');

      final LlmToolCall call = (decision as RouteTools).calls.single;
      expect(call.name, kSkillLoadToolName);
      expect(
          jsonDecode(call.arguments), <String, Object?>{'name': 'code-review'});
    });

    test('未命中 → RoutePass', () async {
      expect(await adapter.route('今天天气怎么样'), isA<RoutePass>());
    });
  });

  group('端到端：接到 Agent Loop 的快路径', () {
    late Context app;
    late _CountingLlm llm;
    late Session session;

    setUp(() {
      app = Context.root();
      session = Session(id: 'fast-path');
      provideTelemetry(app);
      provideTools(app);
      provideSystemPrompt(app);
      llm = _CountingLlm();
      app.provide('llm', llm);
      // Router 必须先于 AgentLoop 装配。
      provideIntentRouter(
        app,
        session: session,
        intents: <Intent>[
          Intent(
            name: 'greeting',
            description: '问候',
            patterns: <Pattern>[RegExp('^你好')],
            action: const DirectAction.respond('你好，有什么可以帮你？'),
          ),
          Intent(
            name: 'weather',
            description: '查天气',
            patterns: <Pattern>[RegExp('^查天气')],
            action: const ToolAction(
              tool: 'weather_now',
              argsTemplate: <String, Object?>{'city': '北京'},
            ),
          ),
        ],
      );
      app.tools.fn(
        'weather_now',
        description: '查天气',
        handler: (ToolContext ctx) async =>
            ToolResult.success('北京晴，26 度', value: '26'),
      );
    });

    tearDown(() => app.dispose());

    test('直接动作命中：零模型调用，会话历史连贯', () async {
      final AgentLoop agent = provideAgentLoop(app, session: session);

      final AgentTurn turn = await agent.run('你好');

      expect(turn.reply, '你好，有什么可以帮你？');
      expect(llm.calls, 0);
      expect(
        session.events.map((SessionEvent e) => e.type),
        <String>[kUserMessageEvent, 'intent/routed', kAssistantMessageEvent],
      );
    });

    test('工具动作命中：预置调用后由模型收口', () async {
      final AgentLoop agent = provideAgentLoop(app, session: session);

      final AgentTurn turn = await agent.run('查天气');

      expect(llm.calls, 1);
      expect(turn.reply, '模型收口');
      expect(turn.steps, hasLength(1));
      expect(turn.steps.single.result.content, '北京晴，26 度');
      expect(
        session.events.map((SessionEvent e) => e.type),
        containsAllInOrder(<String>[
          kUserMessageEvent,
          'intent/routed',
          kAssistantMessageEvent,
          kToolResultEvent,
          kAssistantMessageEvent,
        ]),
      );
    });

    test('未命中：落回完整 Agent Loop', () async {
      final AgentLoop agent = provideAgentLoop(app, session: session);

      final AgentTurn turn = await agent.run('今天天气怎么样');

      expect(llm.calls, 1);
      expect(turn.reply, '模型收口');
      expect(
        session.events.map((SessionEvent e) => e.type),
        isNot(contains('intent/routed')),
      );
    });

    test('命中的遥测事件与未命中的遥测事件都被埋点', () async {
      final AgentLoop agent = provideAgentLoop(app, session: session);
      final InMemoryTelemetry telemetry =
          app.require<InMemoryTelemetry>('telemetry');

      await agent.run('你好');
      await agent.run('今天天气怎么样');

      expect(
        telemetry.recent.map((TelemetryEvent e) => e.name),
        containsAll(<String>['intent.matched', 'intent.missed']),
      );
    });
  });

  test('未显式传 session 时按会话存储里唯一打开的会话记录', () async {
    final Context app = Context.root();
    addTearDown(app.dispose);
    provideTelemetry(app);
    provideTools(app);
    provideSystemPrompt(app);
    final Session session = provideSessions(app).create(id: 'lazy');
    final _CountingLlm llm = _CountingLlm();
    app.provide('llm', llm);

    provideIntentRouter(
      app,
      intents: <Intent>[
        Intent(
          name: 'greeting',
          description: '问候',
          patterns: <Pattern>[RegExp('^你好')],
          action: const DirectAction.respond('你好'),
        ),
      ],
    );
    final AgentLoop agent = provideAgentLoop(app);

    await agent.run('你好');

    expect(
      session.events.map((SessionEvent e) => e.type),
      <String>[kUserMessageEvent, 'intent/routed', kAssistantMessageEvent],
    );
  });
}
