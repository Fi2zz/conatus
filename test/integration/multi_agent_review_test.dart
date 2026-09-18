/// 场景二：多 Agent 审查。
///
/// 链路：team → workflow → tui。
/// Lead Agent 经 `workflow_run` 启动一个 4 节点流程（3 个审查 AgentNode +
/// 1 个汇总 AgentNode，汇总依赖前三个）。workflow 引擎把 AgentNode 交给团队：
/// 并行 spawn 3 个成员各自执行审查任务，全部完成后汇总节点执行，成员被清理。
/// [TeamSubscription] 把团队变更折叠成 [TeamSnapshot]，峰值同时活跃成员数
/// 恰好是并行的直接证据。
library;

import 'dart:async';
import 'package:conatus/conatus.dart';
import 'package:conatus_team/conatus_team.dart';
import 'package:conatus_tui/conatus_tui.dart';
import 'package:conatus_workflow/conatus_workflow.dart';
import 'package:test/test.dart';

import 'helpers/scripted_llm.dart';
import 'helpers/test_harness.dart';

void main() {
  test('多 Agent 审查：3 成员并行 + 汇总依赖，快照峰值 3', () async {
    final TestHarness h = await TestHarness.create(llmScript: <LlmResult>[
      callTool('c1', 'workflow_run', <String, Object?>{'name': 'code-review'}),
      text('已启动多 Agent 审查，正在并行执行'),
      text('性能审查完成：无明显性能瓶颈'),
      text('安全审查完成：未发现安全漏洞'),
      text('产品审查完成：产品角度可接受'),
      text('三份结论已汇总，审查完成'),
    ]);
    addTearDown(h.dispose);

    // 团队 + 流程引擎 + 流程工具（lead 侧 workflow_run）。
    provideAgentTeam(
      h.app,
      session: h.session,
      telemetry: h.telemetry,
    );
    final AgentTeam team = h.app.team;
    final WorkflowEngine engine = provideWorkflow(
      h.app,
      team: team,
      tools: h.app.tools,
      session: h.session,
      telemetry: h.telemetry,
    );
    provideWorkflowTools(h.app);

    // TUI 侧：团队订阅折叠快照，记录变更历史。
    final List<TeamSnapshot> snapshots = <TeamSnapshot>[];
    final TeamSubscription subscription =
        TeamSubscription(team: team, onChanged: snapshots.add);
    addTearDown(subscription.dispose);

    // 审查流程：3 个并行审查节点 + 1 个依赖它们的汇总节点。
    await engine.register(const WorkflowDefinition(
      name: 'code-review',
      version: 1,
      nodes: <WorkflowNode>[
        AgentNode(
          id: 'perf',
          name: '性能审查',
          task: '从性能角度审查这段代码',
          dependsOn: <String>[],
        ),
        AgentNode(
          id: 'sec',
          name: '安全审查',
          task: '从安全角度审查这段代码',
          dependsOn: <String>[],
        ),
        AgentNode(
          id: 'prod',
          name: '产品审查',
          task: '从产品角度审查这段代码',
          dependsOn: <String>[],
        ),
        AgentNode(
          id: 'summary',
          name: '汇总',
          task: '汇总三份审查结论',
          dependsOn: <String>['perf', 'sec', 'prod'],
        ),
      ],
    ));

    final AgentTurn turn = await h.run('从性能、安全、产品三个角度审查这段代码');
    await _waitTerminal(engine, 'code-review-1');

    // 1) Lead 启动了流程，最终输出完成进度。
    expect(turn.reply, contains('审查'));

    // 2) 流程完成，4 个节点（3 审查 + 1 汇总）。
    final WorkflowRun run = engine.run('code-review-1')!;
    expect(run.status, RunStatus.completed);
    expect(run.nodes, hasLength(4));
    expect(
      run.nodes.keys,
      containsAll(<String>['perf', 'sec', 'prod', 'summary']),
    );

    // 3) 汇总节点依赖三个审查节点。
    final WorkflowDefinition definition = engine.definition('code-review')!;
    final WorkflowNode summary =
        definition.nodes.firstWhere((WorkflowNode n) => n.id == 'summary');
    expect(summary.dependsOn, <String>['perf', 'sec', 'prod']);

    // 4) 并行：峰值同时活跃成员数为 3（串行执行峰值只会是 1）。
    final int peak = snapshots.fold(
      0,
      (int max, TeamSnapshot s) =>
          s.activeMembers > max ? s.activeMembers : max,
    );
    expect(peak, 3);

    // 5) 完成态：成员全部清理，spawn 事件被记录。
    expect(team.members, isEmpty);
    h.expectEvent('team.spawn');
    h.expectEvent('team.remove');
  }, timeout: const Timeout(Duration(seconds: 30)));
}

/// 轮询直到流程运行进入终态。
Future<void> _waitTerminal(
  WorkflowEngine engine,
  String runId, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!(engine.run(runId)?.status.isTerminal ?? true)) {
    if (watch.elapsed > timeout) {
      fail('workflow $runId 未在超时内完成: ${engine.run(runId)?.status.name}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
