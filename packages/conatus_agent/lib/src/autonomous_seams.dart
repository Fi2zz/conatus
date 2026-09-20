/// autonomous runner 的可选依赖缝集合。
///
/// 参照 `goal_seams.dart` 的 [GoalSeams] 模式：[AutonomousSeams] 集中承载
/// autonomous 的四个可选依赖（costTracker / approval / telemetry /
/// sessionLog）及其全部使用点——预算读取、审批确认、审计事件（`autonomous.*`）、
/// 埋点（`autonomous.*`）。缺省降级：不预算限制 / 自动批准 / 不埋点 / 不记录。
/// 不从 barrel 导出，属于包内实现细节。
library;

import 'dart:math' show max;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'agent_types.dart';
import 'approval.dart';
import 'autonomous_policy.dart';
import 'autonomous_runner.dart';
import 'goal.dart';
import 'priority_engine.dart';
import 'telemetry.dart';

/// autonomous 的可选依赖缝及其使用点。
class AutonomousSeams {
  AutonomousSeams({
    required this.session,
    this.costTracker,
    this.costOfTurn,
    this.approval,
    this.telemetry,
    this.sessionLog,
  });

  /// 审计事件归属的会话。
  final Session session;

  /// 预算能力缝；null 表示无预算限制。
  final CostTracker? costTracker;

  /// 每轮成本折算钩子（美元）；null 时回退 [costTracker] 今日增量近似。
  final double Function(AgentTurn turn)? costOfTurn;

  /// 审批能力缝；null 表示自动批准。
  final Approval? approval;

  /// 遥测导出器；null 表示不埋点。
  final Telemetry? telemetry;

  /// 审计日志；null 表示不记录。
  final SessionLog? sessionLog;

  final PriorityEngine _priority = PriorityEngine();

  /// 当前累计成本；无 tracker 时为 0。
  double get cost => costTracker?.todayCost ?? 0;

  /// [before] 之后的正成本增量。
  double costDelta(double before) => max(0, cost - before);

  /// 一轮成本：有 [costOfTurn] 钩子用精确折算（负值截 0），否则用
  /// [before] 之后的今日增量近似。
  double turnCost(AgentTurn turn, double before) {
    final double Function(AgentTurn)? hook = costOfTurn;
    if (hook == null) return costDelta(before);
    final double exact = hook(turn);
    return exact < 0 ? 0 : exact;
  }

  /// 经审批确认一次操作；approval 缺省视为自动批准。
  Future<bool> askApproval(String toolName, String description) async {
    final Approval? gate = approval;
    if (gate == null) return true;
    return gate.request(ApprovalRequest(
      id: 'autonomous-${DateTime.now().microsecondsSinceEpoch}',
      toolName: toolName,
      description: description,
    ));
  }

  /// 记一条 `autonomous.*` 审计事件；sessionLog 缺失时静默。
  Future<void> audit(String type, Map<String, Object?> data) async {
    final SessionLog? log = sessionLog;
    if (log == null) return;
    await log.append(SessionEvent.create(
      sessionId: session.id,
      type: type,
      seq: 0,
      data: data,
    ));
  }

  /// 记一轮结束的审计事件（含决策理由：目标优先级得分）。
  Future<void> auditTurn(Goal goal, AgentTurn turn, double costDelta) =>
      audit('autonomous/turn', <String, Object?>{
        'goalId': goal.id,
        'priorityScore': _priority.scoreOf(goal).score,
        'replyLength': turn.reply.length,
        'steps': turn.steps.length,
        'costDelta': costDelta,
      });

  /// 记运行收尾的审计事件。
  Future<void> auditFinished(AutonomousResult result) =>
      audit('autonomous/finished', <String, Object?>{
        'stoppedReason': result.stoppedReason.name,
        'turns': result.turns.length,
        'totalCost': result.totalCost,
        'goalsAdvanced': result.goalsAdvanced,
      });

  /// 发一轮结束的埋点事件。
  void emitTurn(Goal goal, AgentTurn turn, double costDelta) {
    telemetry?.emit(TelemetryEvent('autonomous.round', data: <String, Object?>{
      'goalId': goal.id,
      'replyLength': turn.reply.length,
      'steps': turn.steps.length,
      'costDelta': costDelta,
    }));
  }

  /// 发运行收尾的埋点事件。
  void emitFinished(AutonomousResult result) {
    telemetry
        ?.emit(TelemetryEvent('autonomous.finished', data: <String, Object?>{
      'stoppedReason': result.stoppedReason.name,
      'turns': result.turns.length,
      'totalCost': result.totalCost,
      'goalsAdvanced': result.goalsAdvanced,
    }));
  }
}
