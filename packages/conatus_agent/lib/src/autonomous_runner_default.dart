/// [AutonomousRunner] 的默认实现。
///
/// 只负责生命周期：策略持有、run / stop / isRunning 与结果装配；循环主体
/// 委托 [AutonomousLoop]。可选依赖的集中使用点见 [AutonomousSeams]。
///
/// **注意**：自主运行时要求 [agent] 未挂 [AgentLoop.goalDriver]（`provideGoal`
/// 自动挂载的续行驱动器会与 Runner 自己的轮次记账双算），且应已绑定与
/// [session] 相同的会话；否则需由调用方先摘除驱动器。
library;

import 'dart:async';

import 'package:conatus_foundation/conatus_foundation.dart';
import 'agent_loop.dart';
import 'agent_types.dart';
import 'approval.dart';
import 'autonomous_loop.dart';
import 'autonomous_policy.dart';
import 'autonomous_runner.dart';
import 'autonomous_seams.dart';
import 'goal_service.dart';
import 'telemetry.dart';

/// [AutonomousRunner] 的默认实现。
class DefaultAutonomousRunner implements AutonomousRunner {
  DefaultAutonomousRunner({
    required this.agent,
    required this.goal,
    required this.session,
    required AutonomousPolicy policy,
    CostTracker? costTracker,
    Approval? approval,
    Telemetry? telemetry,
    SessionLog? sessionLog,
    DateTime Function()? clock,
    Future<void> Function(Duration)? sleeper,
  })  : _policy = policy,
        _seams = AutonomousSeams(
          session: session,
          costTracker: costTracker,
          approval: approval,
          telemetry: telemetry,
          sessionLog: sessionLog,
        ),
        _clock = clock ?? DateTime.now,
        _sleeper = sleeper ?? Future<void>.delayed {
    _loop = AutonomousLoop(
      agent: agent,
      goal: goal,
      session: session,
      policy: () => _policy,
      seams: _seams,
      clock: _clock,
      sleeper: _sleeper,
      stopSignal: () => _stopSignal!,
    );
  }

  /// 被驱动的 Agent Loop。
  final AgentLoop agent;

  /// 目标服务。
  final GoalService goal;

  /// 绑定的会话（自主 turn 的事件与审计归属）。
  final Session session;

  final AutonomousSeams _seams;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _sleeper;
  late AutonomousLoop _loop;
  AutonomousPolicy _policy;
  bool _running = false;
  bool _stopped = false;
  Completer<void>? _stopSignal;

  @override
  AutonomousPolicy get policy => _policy;

  @override
  void setPolicy(AutonomousPolicy next) => _policy = next;

  @override
  bool get isRunning => _running;

  @override
  void stop() {
    _stopped = true;
    final Completer<void>? signal = _stopSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
  }

  @override
  Future<AutonomousResult> run() async {
    if (_running) throw StateError('AutonomousRunner 已在运行');
    _running = true;
    _stopSignal = Completer<void>();
    final List<AgentTurn> turns = <AgentTurn>[];
    final List<String> advanced = <String>[];
    double totalCost = 0;
    StopReason reason = StopReason.manualStop;
    try {
      while (!_stopped) {
        final (StopReason? done, double costDelta) =
            await _loop.iterate(turns, advanced);
        totalCost += costDelta;
        if (done != null) {
          reason = done;
          break;
        }
      }
    } finally {
      _running = false;
    }
    // stop() 只影响当次运行（含运行前取消下一次）；结束后复位，runner 可复用。
    _stopped = false;
    final AutonomousResult result = AutonomousResult(
      turns: turns,
      goalsAdvanced: advanced,
      totalCost: totalCost,
      stoppedReason: reason,
    );
    await _seams.auditFinished(result);
    _seams.emitFinished(result);
    return result;
  }
}
