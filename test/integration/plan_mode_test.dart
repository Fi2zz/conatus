/// 场景五：Plan Mode 闭环。
///
/// 链路：plan_mode → approval → agent。
/// 进入 Plan Mode（模拟 `/plan` 命令 → [PlanMode.enter]）后，`plan:policy` 注入
/// system prompt；只读工具放行、`riskLevel >= medium` 的工具被
/// `PLAN_MODE_BLOCKED` 拦截；`exit_plan_mode` 提交计划走 ask_user 审批，批准后
/// Plan Mode 退出，执行阶段的写操作不再被拦截。
library;

import 'dart:async';
import 'package:conatus/conatus.dart';
import 'package:test/test.dart';

import 'helpers/fake_search.dart';
import 'helpers/fake_shell.dart';
import 'helpers/scripted_llm.dart';
import 'helpers/test_harness.dart';

void main() {
  test('Plan Mode 闭环：注入策略 → 拦截写操作 → 审批通过 → 恢复执行', () async {
    final TestHarness h = await TestHarness.create(llmScript: <LlmResult>[
      callTool('c1', 'web_search', <String, Object?>{'query': '北京到上海 高铁'}),
      callTool('c2', 'shell', <String, Object?>{'command': 'ls'}),
      callTool('c3', 'exit_plan_mode', <String, Object?>{
        'goal': '查高铁车次',
        'steps': <Object?>['查车次', '订票'],
      }),
      callTool('c4', 'shell', <String, Object?>{'command': 'ls'}),
      text('完成'),
    ]);
    addTearDown(h.dispose);

    // 外部 IO：假搜索 + 假 shell（medium 风险，plan mode 激活时会被拦）。
    provideSearch(h.app, providers: <SearchProvider>[
      FakeSearchProvider(results: <String, List<SearchResult>>{
        '北京到上海 高铁': <SearchResult>[
          searchResult('G1 高铁', 'https://example.com/g1'),
        ],
      }),
    ]);
    provideWebTools(h.app);
    final FakeShellExecutor shell = FakeShellExecutor();
    h.app.tools.fn(
      'shell',
      description: '执行 shell 命令',
      params: <ParamSpec>[ParamSpec.string('command', required: true)],
      riskLevel: ToolRisk.medium,
      handler: (ToolContext ctx) async {
        final String command = ctx.str('command');
        final ShellRunResult result =
            await shell.run(shell.resolve(ShellExecRequest(command: command)));
        return result.exitCode == 0
            ? ToolResult.success(result.stdout.text)
            : ToolResult.failure(result.stderr.text);
      },
    );

    // 进入 Plan Mode（模拟用户输入 /plan）。
    final PlanMode planMode = providePlanMode(h.app, session: h.session);
    planMode.enter();
    expect(planMode.state, PlanModeState.active);

    // 跑 Agent；中途 exit_plan_mode 会经 ask_user 提问，等待后投递批准。
    final Future<AgentTurn> running = h.agent.run('查一下高铁车次并订票');
    await h.waitForOutput('是否允许执行');
    h.type('可以');
    final AgentTurn turn = await running;

    // 1) system prompt 注入了 plan:policy（kPlanModePolicy 文本）。
    final String system = h.llm.requests.first.first.content;
    expect(system, contains('You are in plan mode'));

    // 2) plan mode 激活时，medium 风险工具被 PLAN_MODE_BLOCKED 拦截。
    final AgentStep blocked = turn.steps.firstWhere(
      (AgentStep s) => s.call.name == 'shell' && s.result.isError,
    );
    expect(blocked.result.error?.code, 'PLAN_MODE_BLOCKED');

    // 3) exit_plan_mode 触发 plan.submitted，审批经 ask_user 完成。
    h.expectEvent('plan.entered');
    h.expectEvent('plan.submitted');
    h.expectEvent('plan.exited');
    h.output.expectContains('是否允许执行 "plan"');

    // 4) 审批通过后 Plan Mode 退出，执行阶段的 shell 不再被拦截。
    expect(planMode.state, PlanModeState.inactive);
    expect(
      turn.steps.any(
          (AgentStep s) => s.call.name == 'shell' && !s.result.isError),
      isTrue,
    );

    // 5) Plan Mode 状态持久化并可恢复。
    expect(
      h.session.events.any((SessionEvent e) => e.type == kPlanModeEvent),
      isTrue,
    );
    expect(restorePlanModeState(h.session), PlanModeState.inactive);

    // 6) 收口并输出计划。
    expect(turn.reply, '完成');
    expect(turn.steps.map((AgentStep s) => s.call.name), <String>[
      'web_search',
      'shell',
      'exit_plan_mode',
      'shell',
    ]);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
