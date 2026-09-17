/// AgentTeam 默认实现：成员生命周期 + 消息系统 + 任务板 + 事件流。
///
/// 复用 [SpawnAgentTool] 的隔离委托思路：每个成员持独立 [Session] 与
/// [AgentLoop]，通过 [MemberRuntime] 串行处理消息。生命周期绑定队长
/// [Context]——host 释放时通过 [Context.onDispose] 级联清理。任务板委托
/// [TeamBoard]；事件通过 [StreamController] 广播。
///
/// 运行时集成（Step 5-8）通过 [TeamHooks] 可选注入：任务追踪 / 会话
/// 日志 / 审批 / 遥测四条 seam 全部可选，缺省 no-op。
library;

import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';

import 'agent_team.dart';
import 'team_board.dart';
import 'team_events.dart';
import 'team_hooks.dart';
import 'team_member_runtime.dart';
import 'team_task.dart';
import 'team_task_tracker.dart';
import 'teammate.dart';

/// [AgentTeam] 的默认实现。
class AgentTeamImpl implements AgentTeam {
  /// 直接构造（测试或自定义装配用）；运行时推荐走 [provideAgentTeam]。
  AgentTeamImpl({
    required this.leadId,
    required this.host,
    required this.llm,
    required this.tools,
    this.defaultTools,
    this.maxMembers = 8,
    this.hooks,
  });

  @override
  final String leadId;
  final Context host;
  final LlmProvider llm;
  final ToolRegistry tools;
  final List<String>? defaultTools;
  final int maxMembers;
  final TeamHooks? hooks;

  final StreamController<AgentTeamEvent> _changes =
      StreamController<AgentTeamEvent>.broadcast();
  final Map<String, Teammate> _teammates = <String, Teammate>{};
  final Map<String, MemberRuntime> _runtimes = <String, MemberRuntime>{};
  final Map<String, String?> _trackerIds = <String, String?>{};
  final TeamBoard _board = TeamBoard();
  int _seq = 0;

  @override
  List<Teammate> get members => List<Teammate>.unmodifiable(_teammates.values);

  @override
  List<TeamTask> get tasks => _board.all;

  @override
  Stream<AgentTeamEvent> get changes => _changes.stream;

  @override
  Future<Teammate> spawn({
    required String name,
    List<String>? tools,
    String? systemPrompt,
  }) async {
    if (_teammates.length >= maxMembers) {
      throw TeamException('max-members', '成员数已达上限 $maxMembers');
    }
    final List<String> toolList = tools ?? _defaultTools();
    if (!await (hooks?.checkSpawnApproval(name: name, tools: toolList) ??
        Future<bool>.value(true))) {
      throw TeamException('approval-denied', '创建成员「$name」未获批');
    }
    _seq++;
    final String id = 'teammate-$_seq';
    final Teammate mate = Teammate(
      id: id,
      name: name,
      role: TeamRole.member,
      status: TeammateStatus.idle,
      tools: toolList,
      createdAt: DateTime.now(),
      systemPrompt: systemPrompt,
    );
    final Session ms = Session(id: '$id-session');
    final MemberRuntime runtime = MemberRuntime(
      id: id,
      session: ms,
      loop: AgentLoop(
        llm: llm,
        tools: _buildChildTools(toolList),
        session: ms,
        defaultSystemPrompt: systemPrompt ?? '你是团队成员「$name」，完成任务后简短回复结论。',
      ),
      onStatus: (TeammateStatus next) => _mutate(id, next),
    );
    host.onDispose(runtime.dispose);
    _teammates[id] = mate;
    _runtimes[id] = runtime;
    _trackerIds[id] = await hooks?.onSpawn(
      teammateId: id,
      name: name,
      leadId: leadId,
      tools: toolList,
    );
    _changes.add(TeammateSpawned(mate));
    return mate;
  }

  @override
  Future<void> send(String teammateId, String message) async {
    final MemberRuntime? rt = _runtimes[teammateId];
    if (rt == null) {
      throw TeamException('not-found', '成员 "$teammateId" 不存在');
    }
    final Teammate? mate = _teammates[teammateId];
    if (mate != null && mate.isTerminal) {
      throw TeamException('terminal', '成员 "${mate.name}" 已终态');
    }
    hooks?.onSend(from: leadId, to: teammateId, message: message);
    _changes.add(TeamMessageSent(leadId, teammateId, message));
    await rt.send(message);
  }

  @override
  Future<String> ask(String teammateId, String message) async {
    final MemberRuntime? rt = _runtimes[teammateId];
    if (rt == null) {
      throw TeamException('not-found', '成员 "$teammateId" 不存在');
    }
    final Teammate? mate = _teammates[teammateId];
    if (mate != null && mate.isTerminal) {
      throw TeamException('terminal', '成员 "${mate.name}" 已终态');
    }
    hooks?.onSend(from: leadId, to: teammateId, message: message);
    _changes.add(TeamMessageSent(leadId, teammateId, message));
    final TeamTurn turn = await rt.send(message);
    return turn.reply;
  }

  @override
  Future<Teammate> wait(String teammateId, {Duration? timeout}) async {
    final MemberRuntime? rt = _runtimes[teammateId];
    if (rt == null) {
      throw TeamException('not-found', '成员 "$teammateId" 不存在');
    }
    await rt.wait(timeout: timeout);
    return _teammates[teammateId]!;
  }

  @override
  Future<List<Teammate>> waitAll({Duration? timeout}) async {
    await Future.wait(
        _runtimes.values.map((MemberRuntime rt) => rt.wait(timeout: timeout)));
    return members;
  }

  @override
  Future<void> interrupt(String teammateId) async {
    final MemberRuntime? rt = _runtimes[teammateId];
    if (rt == null) {
      throw TeamException('not-found', '成员 "$teammateId" 不存在');
    }
    if (!await (hooks?.checkInterruptApproval(teammateId: teammateId) ??
        Future<bool>.value(true))) {
      throw TeamException('approval-denied', '中断成员 "$teammateId" 未获批');
    }
    await rt.interrupt();
  }

  @override
  Future<void> remove(String teammateId) async {
    final MemberRuntime? rt = _runtimes.remove(teammateId);
    if (rt == null) {
      throw TeamException('not-found', '成员 "$teammateId" 不存在');
    }
    rt.dispose();
    final Teammate? mate = _teammates.remove(teammateId);
    final bool completed = mate?.status != TeammateStatus.failed;
    _trackerIds.remove(teammateId);
    await hooks?.onRemove(
      teammateId: teammateId,
      completed: completed,
    );
    if (mate != null && !mate.isTerminal) {
      _changes.add(
          TeammateStatusChanged(mate.copyWith(status: TeammateStatus.done)));
    }
  }

  @override
  Future<TeamTask> createTask({
    required String description,
    List<String> dependsOn = const <String>[],
    String? assigneeId,
  }) async {
    final TeamTask task = _board.create(
      description: description,
      dependsOn: dependsOn,
      assigneeId: assigneeId,
    );
    hooks?.onTaskCreated(
      taskId: task.id,
      description: description,
      assigneeId: assigneeId,
    );
    _changes.add(TeamTaskCreated(task));
    return task;
  }

  @override
  Future<TeamTask> claimTask(String taskId, String teammateId,
      {int? version}) async {
    final TeamTask task = _board.claim(taskId, teammateId, version: version);
    _changes.add(TeamTaskChanged(task));
    _mutate(teammateId, TeammateStatus.working);
    return task;
  }

  @override
  Future<TeamTask> completeTask(String taskId, String teammateId,
      {Object? result, int? version}) async {
    final TeamTask task =
        _board.complete(taskId, teammateId, result: result, version: version);
    _changes.add(TeamTaskChanged(task));
    return task;
  }

  @override
  Future<TeamTask> releaseTask(String taskId, String teammateId,
      {int? version}) async {
    final TeamTask task = _board.release(taskId, teammateId, version: version);
    _changes.add(TeamTaskChanged(task));
    return task;
  }

  @override
  TeamTask? task(String id) => _board.get(id);

  @override
  List<TeamTask> claimableBy(String teammateId) =>
      _board.claimableBy(teammateId);

  @override
  void dispose() {
    for (final MemberRuntime rt in _runtimes.values) {
      rt.dispose();
    }
    _runtimes.clear();
    _teammates.clear();
    _changes.close();
  }

  void _mutate(String teammateId, TeammateStatus next) {
    final Teammate? mate = _teammates[teammateId];
    if (mate == null || mate.status == next) return;
    final Teammate updated = mate.copyWith(status: next);
    _teammates[teammateId] = updated;
    _changes.add(TeammateStatusChanged(updated));
  }

  List<String> _defaultTools() {
    if (defaultTools != null) {
      return <String>[
        for (final String n in defaultTools!)
          if (tools.get(n) != null) n,
      ];
    }
    return <String>[
      for (final String n in tools.names)
        if (tools.get(n)!.riskLevel != ToolRisk.high) n,
    ];
  }

  ToolRegistry _buildChildTools(List<String> toolList) {
    final ToolRegistry childTools = ToolRegistry();
    for (final String n in toolList) {
      final Tool? t = tools.get(n);
      if (t != null) childTools.register(t);
    }
    return childTools;
  }
}

/// `ctx.team`：当前上下文可见的 [AgentTeam]。
extension TeamContext on Context {
  /// 取当前上下文可见的 [AgentTeam]（未提供时抛 [StateError]）。
  AgentTeam get team => require<AgentTeam>('team');
}

/// 把 [AgentTeam] 作为 `'team'` 服务提供到上下文。
///
/// 依赖 `llm`、`tools`（必需）；运行时 seam（[taskTracker] / [session] /
/// [approval] / [telemetry]）全部可选，缺省 no-op。成员子上下文不派生，
/// 成员 [Session] 独立持有；runtime 的清理通过 [Context.onDispose] 绑定
/// [ctx]，ctx 释放时级联。返回的 [Disposer] 撤销服务注册。
Disposer provideAgentTeam(
  Context ctx, {
  String? leadId,
  LlmProvider? llm,
  ToolRegistry? tools,
  List<String>? defaultTools,
  int maxMembers = 8,
  TeamTaskTracker? taskTracker,
  Session? session,
  Approval? approval,
  Telemetry? telemetry,
}) {
  final TeamHooks? hooks = (taskTracker == null &&
          session == null &&
          approval == null &&
          telemetry == null)
      ? null
      : TeamHooks(
          taskTracker: taskTracker,
          session: session,
          approval: approval,
          telemetry: telemetry,
        );
  final AgentTeamImpl team = AgentTeamImpl(
    leadId: leadId ?? ctx.name,
    host: ctx,
    llm: llm ?? ctx.require<LlmProvider>('llm'),
    tools: tools ?? ctx.require<ToolRegistry>('tools'),
    defaultTools: defaultTools,
    maxMembers: maxMembers,
    hooks: hooks,
  );
  ctx.onDispose(team.dispose);
  return ctx.provide('team', team);
}
