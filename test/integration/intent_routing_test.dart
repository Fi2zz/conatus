/// 场景八：意图路由短路 Agent Loop。
///
/// 链路：intent → router（`conatus_agent` 的确定性快路径）→ agent / tools / session。
/// 正则或向量命中的输入不产生模型调用：直接动作直接收口（零 `llm/request`），
/// 工具动作预置调用后由模型收口；未命中才落回完整 Agent Loop。命中信息经
/// `intent/routed` 会话事件与遥测外露。
library;

import 'package:conatus/conatus.dart';
import 'package:test/test.dart';

import 'helpers/scripted_llm.dart';
import 'helpers/test_harness.dart';

/// 装配一个只认「你好」的意图路由器，并接到 Agent Loop 的快路径。
void _installRouter(Context app, Session session) {
  provideIntentRouter(
    app,
    session: session,
    intents: <Intent>[
      Intent(
        name: 'greeting',
        description: '问候',
        patterns: <Pattern>[RegExp(r'^(你好|hi|hello)')],
        action: const DirectAction.respond('你好，有什么可以帮你？'),
      ),
    ],
  );
}

void main() {
  test('意图命中短路 Agent Loop：零模型调用、会话历史连贯', () async {
    final TestHarness h = await TestHarness.create(
      llmScript: <LlmResult>[text('模型收口')],
      configure: _installRouter,
    );
    addTearDown(h.dispose);

    final AgentTurn turn = await h.run('你好');

    expect(turn.reply, '你好，有什么可以帮你？');
    expect(turn.steps, isEmpty);
    expect(h.llm.requests, isEmpty, reason: '命中意图不应调用模型');
    expect(
      h.session.events.map((SessionEvent e) => e.type),
      <String>[kUserMessageEvent, 'intent/routed', kAssistantMessageEvent],
    );
    h.expectEvent('intent.matched', data: <String, Object?>{
      'name': 'greeting',
      'source': 'regex',
    });
    h.expectNoEvent('llm.request');
  });

  test('未命中落回完整 Agent Loop 并记录未命中埋点', () async {
    final TestHarness h = await TestHarness.create(
      llmScript: <LlmResult>[text('模型收口')],
      configure: _installRouter,
    );
    addTearDown(h.dispose);

    final AgentTurn turn = await h.run('今天天气怎么样');

    expect(turn.reply, '模型收口');
    expect(h.llm.requests, hasLength(1));
    expect(
      h.session.events.map((SessionEvent e) => e.type),
      isNot(contains('intent/routed')),
    );
    h.expectEvent('intent.missed', data: <String, Object?>{
      'input': '今天天气怎么样',
    });
  });

  test('工具动作命中：预置调用后由模型收口', () async {
    final TestHarness h = await TestHarness.create(
      llmScript: <LlmResult>[text('北京今天晴，26 度。')],
      configure: (Context app, Session session) {
        provideIntentRouter(
          app,
          session: session,
          intents: <Intent>[
            Intent(
              name: 'weather',
              description: '查天气',
              patterns: <Pattern>[RegExp(r'^查天气')],
              action: const ToolAction(
                tool: 'weather_now',
                argsTemplate: <String, Object?>{'city': '北京'},
              ),
            ),
          ],
        );
        app.tools.fn(
          'weather_now',
          description: '查当前天气',
          handler: (ToolContext ctx) async =>
              ToolResult.success('北京晴，26 度', value: '26'),
        );
      },
    );
    addTearDown(h.dispose);

    final AgentTurn turn = await h.run('查天气');

    expect(turn.reply, '北京今天晴，26 度。');
    expect(turn.steps, hasLength(1));
    expect(turn.steps.single.result.content, '北京晴，26 度');
    expect(h.llm.requests, hasLength(1), reason: '工具动作由模型收口，恰好一次');
    expect(
      h.session.events.map((SessionEvent e) => e.type),
      containsAllInOrder(<String>[
        kUserMessageEvent,
        'intent/routed',
        kAssistantMessageEvent,
        kToolResultEvent,
        kAssistantMessageEvent,
      ]),
    );
  });
}
