// conatus_team 端到端 Demo：完全离线，无需任何 API Key。
//
// 演示多智能体协作的完整链路：装配团队（四条 seam 全接通）→ 并发审查
// → Maker-Checker 修订 → 任务板 DAG → 中途移除 → 观测面板。
//
// 运行：
//   cd packages/conatus_team
//   dart run example/demo.dart

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_tasks/conatus_tasks.dart';
import 'package:conatus_team/conatus_team.dart';

import 'demo_board_scenario.dart';
import 'demo_model.dart';
import 'demo_report.dart';
import 'demo_scenarios.dart';
import 'task_center_tracker.dart';

Future<void> main() async {
  final Context app = Context.root(name: 'team-demo');

  // ─ 基础设施：工具 / 可观测性 / 模型 / 队长会话 ──────────────
  final ToolRegistry tools = provideTools(app);
  final InMemoryTelemetry telemetry = InMemoryTelemetry();
  provideTelemetry(app, telemetry: telemetry);
  instrumentTools(app);
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[TeamDemoModel()]));
  final Session session = provideSessions(app).create(id: 'lead');

  // ── TaskCenter：成员工作将作为 subAgent 任务落进任务树 ───────
  final TaskCenter tasks =
      provideTaskCenter(app, session: session, telemetry: telemetry);

  // ── 团队：四条 seam 全接通（不接也能跑，缺省 no-op）──────────
  provideAgentTeam(
    app,
    session: session,
    telemetry: telemetry,
    approval: RuleBasedApproval(allow: (ApprovalRequest _) => true),
    taskTracker: TaskCenterTeamTracker(tasks),
  );
  final AgentTeam team = app.team;
  provideTeamTools(app, team: team, tools: tools);
  print('已注册 ${tools.names.length} 个工具（含 10 个团队工具）');

  // ── 四个场景 ────────────────────────────────────────────────
  await scenarioConcurrent(team);
  await scenarioMakerChecker(team);
  await scenarioBoard(team, tools);
  await scenarioRemove(team, '产品');

  printReport(team: team, tasks: tasks, session: session, telemetry: telemetry);

  app.dispose();
  print('\n完成。');
}