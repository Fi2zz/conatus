/// 场景六：Goal 续行。
///
/// 链路：goal → agent → task_center。
/// 用户设置长期目标后，AgentLoop 每轮收口自动经 [GoalRoundDriver] 续行：
/// 轮次递增、再次驱动 Agent；目标完成（`complete_goal`）后停止续行。
library;

import 'package:conatus/conatus.dart';
import 'package:test/test.dart';

import 'helpers/scripted_llm.dart';
import 'helpers/test_harness.dart';

void main() {
  test('Goal 续行：创建 → 自动推进两轮 → 检测变化 → 完成', () async {
    final TestHarness h = await TestHarness.create(llmScript: <LlmResult>[
      callTool('c1', 'create_goal', <String, Object?>{
        'text': '盯明天的机票价格，有变化就告诉我',
      }),
      text('目标已创建，我先看看价格'),
      text('价格还没变化'),
      callTool('c3', 'complete_goal'),
      text('价格从 800 涨到 1000，目标完成'),
    ]);
    addTearDown(h.dispose);

    // goal 完成路径走自动批准，避免中途 ask_user 提问。
    provideGoal(
      h.app,
      session: h.session,
      approval: AutoApproval(true),
    );
    provideTaskCenter(h.app, session: h.session);

    final AgentTurn turn = await h.run('帮我盯着明天的机票价格，有变化告诉我');

    // 1) Goal 被创建且推进了轮次。
    final Goal goal = h.app.goal.current!;
    expect(goal.status, GoalStatus.completed);
    expect(goal.round, 2); // 创建后 0，续行驱动两轮 → 2
    expect(goal.text, contains('机票价格'));

    // 2) 事件序列：创建 → 推进 → 完成。
    h.expectEvent('goal.created', data: <String, Object?>{'status': 'active'});
    h.expectEvent('goal.advanced');
    h.expectEvent('goal.completed', data: <String, Object?>{'status': 'completed'});

    // 3) 检测到变化后输出。
    h.expectReplyContains('价格');

    // 4) 续行驱动器把轮次写进了 system prompt（goal 段）。
    final List<String> allSystem = <String>[
      for (final List<LlmMessage> request in h.llm.requests)
        request.first.content,
    ];
    expect(allSystem.any((String s) => s.contains('[当前目标]')), isTrue);

    // 5) Goal 完成态持久化到 Session，关联任务都已终态。
    expect(
      h.session.events.any((SessionEvent e) => e.type == kGoalEvent),
      isTrue,
    );
    expect(h.app.tasks.active, isEmpty);

    expect(turn.reply, contains('价格'));
  }, timeout: const Timeout(Duration(seconds: 30)));
}
