/// 场景一：终端订票。
///
/// 链路：ask_user → llm → browser_use → approval。
/// 用户用自然语言发起订票，Agent 经浏览器工具导航、读快照并给出车次候选；
/// 用户确认后提交表单（`browser_submit`，high risk）被 approval 拦截，经
/// ask_user 审批放行后完成下单。
library;

import 'package:conatus/conatus.dart';
import 'package:test/test.dart';

import 'helpers/fake_browser.dart';
import 'helpers/scripted_llm.dart';
import 'helpers/test_harness.dart';

void main() {
  test('终端订票：导航 → 读快照 → 候选 → 高危提交经审批 → 订单号', () async {
    final TestHarness h = await TestHarness.create(llmScript: <LlmResult>[
      callTool('c1', 'browser_navigate',
          <String, Object?>{'url': 'https://example.com/trains'}),
      callTool('c2', 'browser_snapshot'),
      text('找到三趟车，最快的是早上 8 点，要订吗？'),
      callTool('c3', 'browser_submit', <String, Object?>{
        'form': 'id_card',
        'value': '110101199001011234',
      }),
      text('订好了，订单号是 TS-20260918-001'),
    ]);
    addTearDown(h.dispose);

    // 假浏览器：快照返回三趟车，提交成功。
    final FakeBrowserUseProvider browser = FakeBrowserUseProvider()
      ..stub(
        'browser_snapshot',
        '北京 → 上海：\n1. G1 08:00 4h28m\n2. G3 09:00 4h35m\n3. G5 10:00 4h40m',
      )
      ..stub('browser_submit', '订单已提交');
    provideBrowserUse(
      h.app,
      provider: browser,
      session: h.session,
      telemetry: h.telemetry,
    );
    await h.settle(); // 等浏览器工具异步注册进 ToolRegistry

    // 轮 1：导航 + 读快照 + 给出候选。
    final AgentTurn first = await h.run('帮我在那个网站上订一张明天去北京的票');

    // 轮 2：确认订票 → 填身份证（high risk）→ 审批 → 下单。
    final Future<AgentTurn> second = h.agent.run('可以');
    await h.waitForAsk();
    h.type('可以');
    final AgentTurn last = await second;

    // 1) 用户输入被正确注入 Agent。
    expect(
      h.llm.requests.first.any((LlmMessage m) =>
          m.role == 'user' && m.content.contains('订一张明天去北京的票')),
      isTrue,
    );

    // 2) 浏览器导航到正确 URL，快照被读取。
    expect(browser.actions.first.tool, 'browser_navigate');
    expect(browser.actions.first.args['url'], 'https://example.com/trains');
    expect(browser.actions.any((BrowserCall a) => a.tool == 'browser_snapshot'),
        isTrue);

    // 3) 车次信息回填进模型上下文（快照后一次的请求含快照文本）。
    expect(
      h.llm.requests[2].any((LlmMessage m) => m.content.contains('G1 08:00')),
      isTrue,
    );

    // 4) 候选输出与最终订单号。
    expect(first.reply, contains('三趟车'));
    expect(last.reply, contains('订单号'));

    // 5) 高危操作触发审批，批准后继续。
    h.expectEvent('approval.requested', data: <String, Object?>{'tool': 'browser_submit'});
    h.expectEvent('approval.decided', data: <String, Object?>{'approved': true});
    expect(
      browser.actions.where((BrowserCall a) => a.tool == 'browser_submit'),
      hasLength(1),
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}
