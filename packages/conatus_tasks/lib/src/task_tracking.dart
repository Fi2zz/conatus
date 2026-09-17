/// task 插件的运行时接入：把 Agent Loop / spawn_agent / shell / schedule
/// 的执行挂到 [TaskCenter] 上。
///
/// 依赖方向是「组件接入中心」而非「中心依赖组件」：本文件的装饰器由
/// [provideTaskTracking] 在装配时一次性挂好，Agent Loop / sub_agent /
/// schedule / shell 的现有代码零改动。
library;

import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_schedule/conatus_schedule.dart';
import 'task.dart';
import 'task_center.dart';

/// `spawn_agent` 工具名（与 sub_agent 插件一致；该插件未导出常量）。
const String kSpawnAgentToolName = 'spawn_agent';

/// 轮次追踪 + `spawn_agent` 中间件的持有者。每个被追踪的会话一个实例。
class TaskTracking implements AgentTurnTracker {
  /// 提交任务 [TaskCenter]；[ctx] 用于惰性解析 `goal` / `planMode` 服务
  /// 写入任务 metadata（可空，缺省不关联）。
  TaskTracking({required this.tasks, Context? ctx}) : _ctx = ctx;

  /// 任务中心。
  final TaskCenter tasks;

  final Context? _ctx;
  String? _currentTurnTaskId;

  /// 当前 Agent Turn 的任务 id（无活跃轮次时为 null）。
  String? get currentTurnTaskId => _currentTurnTaskId;

  @override
  Future<void> beginTurn(String userInput) async {
    final Task task = await tasks.create(
      kind: TaskKind.agentTurn,
      description: '处理: $userInput',
      metadata: <String, Object?>{
        if (_resolveGoalId() case final String goalId) 'goalId': goalId,
        if (_planModeActive()) 'planMode': true,
      },
    );
    _currentTurnTaskId = task.id;
    await tasks.update(task.id, status: TaskStatus.running);
  }

  @override
  Future<void> endTurn({Object? result, Object? error}) async {
    final String? id = _currentTurnTaskId;
    _currentTurnTaskId = null;
    if (id == null) return;
    if (error != null) {
      await tasks.update(id, status: TaskStatus.failed, error: error);
      return;
    }
    await tasks.update(id, status: TaskStatus.completed, result: result);
  }

  String? _resolveGoalId() => _ctx?.get<GoalService>('goal')?.current?.id;

  bool _planModeActive() =>
      _ctx?.get<PlanMode>('planMode')?.state == PlanModeState.active;

  /// 拦 `spawn_agent` 调用的中间件：为每次委托创建 subAgent 任务，
  /// 挂在当前轮次任务下；其余工具调用原样放行。子 Agent 的结局从结果值
  /// 判定（`value['status'] == 'failed'`，spawn_agent 会把子 Agent 异常
  /// 收敛进结果值而非失败结果）。
  ToolMiddleware get spawnAgentMiddleware =>
      (ToolCall call, Future<ToolResult> Function() next) async {
        if (call.name != kSpawnAgentToolName) return next();
        final Task task = await tasks.create(
          kind: TaskKind.subAgent,
          description: '子 Agent: ${call.arguments['task'] ?? ''}',
          parentTaskId: _currentTurnTaskId,
          metadata: <String, Object?>{
            if (call.arguments['tools'] != null)
              'tools': call.arguments['tools'],
            if (call.arguments['max_rounds'] != null)
              'maxRounds': call.arguments['max_rounds'],
          },
        );
        await tasks.update(task.id, status: TaskStatus.running);
        final ToolResult result = await next();
        final Object? value = result.value;
        final bool subFailed =
            result.isError || (value is Map && value['status'] == 'failed');
        if (subFailed) {
          await tasks.update(task.id,
              status: TaskStatus.failed,
              error: value is Map ? value['output'] : result.content);
        } else {
          await tasks.update(task.id,
              status: TaskStatus.completed, result: value);
        }
        return result;
      };
}

/// 给 [ShellExecutor] 加任务追踪的装饰器：每次前台/后台执行建一个
/// shell 任务，进程落定时按退出码置 completed / failed。
class TrackingShellExecutor implements ShellExecutor {
  /// 包装 [inner]；每个被追踪的命令在 [tasks] 上建任务。
  TrackingShellExecutor({required this.inner, required this.tasks});

  /// 被包装的执行器。
  final ShellExecutor inner;

  /// 任务中心。
  final TaskCenter tasks;

  @override
  ShellExecSpec resolve(ShellExecRequest request) => inner.resolve(request);

  @override
  Future<ShellRunResult> run(ShellExecSpec spec) async {
    final Task task = await _begin(spec);
    final ShellRunResult result = await inner.run(spec);
    await _finish(task.id, result.exitCode);
    return result;
  }

  @override
  Future<ShellProcess> start(ShellExecSpec spec) async {
    final Task task = await _begin(spec);
    final ShellProcess process = await inner.start(spec);
    unawaited(_track(task.id, process));
    return process;
  }

  Future<Task> _begin(ShellExecSpec spec) async {
    final Task task = await tasks.create(
      kind: TaskKind.shell,
      description: 'Shell: ${spec.command}',
      metadata: <String, Object?>{'command': spec.command},
    );
    await tasks.update(task.id, status: TaskStatus.running);
    return task;
  }

  Future<void> _track(String id, ShellProcess process) async {
    try {
      await process.done;
      await _finish(id, process.exitCode);
    } on TaskException {
      // 任务中心已释放或任务已终态：状态追踪让位给执行结果本身。
    }
  }

  Future<void> _finish(String id, int? exitCode) => tasks.update(
        id,
        status: exitCode == 0 ? TaskStatus.completed : TaskStatus.failed,
        result: <String, Object?>{'exitCode': exitCode},
      );
}

/// 包装提醒交付：每次交付建一个 schedule 任务，按交付结果落定。
///
/// 直接适配 `provideScheduleRuntime` 的 `deliver` 参数；cron 的两参交付
/// 在装配方处自行适配后调用。
ScheduleDelivery trackScheduleDelivery(
  TaskCenter tasks,
  ScheduleDelivery deliver,
) {
  return (String text) async {
    final Task task = await tasks.create(
      kind: TaskKind.schedule,
      description: '提醒: $text',
    );
    await tasks.update(task.id, status: TaskStatus.running);
    final bool delivered = await deliver(text);
    await tasks.update(
      task.id,
      status: delivered ? TaskStatus.completed : TaskStatus.failed,
    );
    return delivered;
  };
}
