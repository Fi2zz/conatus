/// autonomous runner 插件：让 Agent 在没有用户输入的情况下主动运行。
///
/// [AutonomousRunner] 在策略（[AutonomousPolicy]）的硬约束（预算、时间窗口、
/// 轮次上限、工具白名单/黑名单）下循环驱动 [AgentLoop]：约束检查 → 目标选择 →
/// 单轮执行 → 审计/埋点 → 人类介入检查 → 目标推进。每个决策（选择的目标、
/// 停止原因、成本）都写入审计日志与遥测，保证可解释（HANDOFF-15 §2）。
/// 装配见 [provideAutonomousRunner]；默认实现见 `autonomous_runner_default.dart`。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'agent_loop.dart';
import 'agent_types.dart';
import 'approval.dart';
import 'autonomous_policy.dart';
import 'autonomous_runner_default.dart';
import 'goal_service.dart';
import 'telemetry.dart';

/// 自主运营的续行提示：Runner 代用户注入的下一轮输入。
const String kAutonomousContinuationPrompt = '[系统] 自主运营：继续推进当前目标。';

/// 自主运行结果。
class AutonomousResult {
  const AutonomousResult({
    required this.turns,
    required this.goalsAdvanced,
    required this.totalCost,
    required this.stoppedReason,
  });

  /// 本轮运行产生的全部轮次（含超时空轮）。
  final List<AgentTurn> turns;

  /// 被推进过的目标 id。
  final List<String> goalsAdvanced;

  /// 累计成本（[CostTracker.todayCost] 正增量之和；无 tracker 时为 0）。
  final double totalCost;

  /// 停止原因。
  final StopReason stoppedReason;
}

/// 停止原因。
enum StopReason {
  /// 正常完成（无目标或目标已终态）。
  completed,

  /// 预算超限。
  budgetExceeded,

  /// 时间窗口结束。
  windowEnded,

  /// 达到最大轮次。
  maxRoundsReached,

  /// 需要人类介入。
  humanRequired,

  /// 手动停止。
  manualStop,
}

/// 自主运行器。
abstract class AutonomousRunner {
  /// 启动自主运行。同一时刻只允许一次运行，重复调用抛 [StateError]。
  Future<AutonomousResult> run();

  /// 停止。正在等待时间窗口的睡眠也会被中断，`run()` 以 [StopReason.manualStop] 收尾。
  void stop();

  /// 是否正在运行。
  bool get isRunning;

  /// 注册策略。
  void setPolicy(AutonomousPolicy policy);

  /// 当前策略。
  AutonomousPolicy get policy;
}

/// `ctx.autonomousRunner`：当前上下文可见的自主运行器。
extension AutonomousRunnerContext on Context {
  /// 取当前上下文可见的 [AutonomousRunner]（未提供时抛 [StateError]）。
  AutonomousRunner get autonomousRunner =>
      require<AutonomousRunner>('autonomousRunner');
}

/// 提供 `'autonomousRunner'` 服务。
///
/// 依赖（全部可选，缺省时降级）：`policy` 缺省 [DefaultAutonomousPolicy]；
/// `costTracker` 缺省无预算限制；`approval` 缺省自动批准；`telemetry` 缺省
/// 无埋点；`sessionLog` 缺省不记录。未显式传入的可选依赖从上下文惰性解析。
///
/// **注意**：传给 [agent] 的 AgentLoop 不应挂 [AgentLoop.goalDriver]（由
/// `provideGoal` 自动挂载的续行驱动器会与 Runner 自己的轮次记账双算），
/// 且应已绑定与 [session] 相同的会话（自主 turn 的事件写入该会话）。
AutonomousRunner provideAutonomousRunner(
  Context ctx, {
  required AgentLoop agent,
  required GoalService goal,
  required Session session,
  AutonomousPolicy? policy,
  CostTracker? costTracker,
  Approval? approval,
  Telemetry? telemetry,
  SessionLog? sessionLog,
}) {
  final AutonomousRunner resolved = DefaultAutonomousRunner(
    agent: agent,
    goal: goal,
    session: session,
    policy: policy ?? const DefaultAutonomousPolicy(),
    costTracker: costTracker ?? ctx.get<CostTracker>('costTracker'),
    approval: approval ?? ctx.get<Approval>('approval'),
    telemetry: telemetry ?? ctx.get<Telemetry>('telemetry'),
    sessionLog: sessionLog ?? ctx.get<SessionLog>('sessionLog'),
  );
  ctx.provide('autonomousRunner', resolved);
  return resolved;
}
