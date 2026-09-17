/// TeamSubscription 测试：事件驱动的快照重建与释放。
library;

import 'dart:async';

import 'package:conatus_team/conatus_team.dart';
import 'package:conatus_tui/conatus_tui.dart';
import 'package:test/test.dart';

/// 手写团队测试替身：用 [emit] 注入事件，快照从当前列表读取。
class FakeAgentTeam implements AgentTeam {
  final List<Teammate> _members = <Teammate>[];
  final List<TeamTask> _tasks = <TeamTask>[];
  final StreamController<AgentTeamEvent> _events =
      StreamController<AgentTeamEvent>.broadcast();

  @override
  String get leadId => 'lead';

  @override
  List<Teammate> get members => List<Teammate>.unmodifiable(_members);

  @override
  List<TeamTask> get tasks => List<TeamTask>.unmodifiable(_tasks);

  @override
  Stream<AgentTeamEvent> get changes => _events.stream;

  void addMember(Teammate mate) {
    _members.removeWhere((Teammate m) => m.id == mate.id);
    _members.add(mate);
  }

  void addTask(TeamTask task) {
    _tasks.removeWhere((TeamTask t) => t.id == task.id);
    _tasks.add(task);
  }

  void emit(AgentTeamEvent event) => _events.add(event);

  @override
  Future<Teammate> spawn({
    required String name,
    List<String>? tools,
    String? systemPrompt,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> send(String teammateId, String message) =>
      throw UnimplementedError();

  @override
  Future<String> ask(String teammateId, String message) =>
      throw UnimplementedError();

  @override
  Future<Teammate> wait(String teammateId, {Duration? timeout}) =>
      throw UnimplementedError();

  @override
  Future<List<Teammate>> waitAll({Duration? timeout}) =>
      throw UnimplementedError();

  @override
  Future<void> interrupt(String teammateId) => throw UnimplementedError();

  @override
  Future<void> remove(String teammateId) => throw UnimplementedError();

  @override
  Future<TeamTask> createTask({
    required String description,
    List<String> dependsOn = const <String>[],
    String? assigneeId,
  }) =>
      throw UnimplementedError();

  @override
  Future<TeamTask> claimTask(
    String taskId,
    String teammateId, {
    int? version,
  }) =>
      throw UnimplementedError();

  @override
  Future<TeamTask> completeTask(
    String taskId,
    String teammateId, {
    Object? result,
    int? version,
  }) =>
      throw UnimplementedError();

  @override
  Future<TeamTask> releaseTask(
    String taskId,
    String teammateId, {
    int? version,
  }) =>
      throw UnimplementedError();

  @override
  TeamTask? task(String id) => throw UnimplementedError();

  @override
  List<TeamTask> claimableBy(String teammateId) => throw UnimplementedError();

  @override
  void dispose() {
    _events.close();
  }
}

Teammate _mate(String id, TeammateStatus status) => Teammate(
      id: id,
      name: id,
      role: TeamRole.member,
      status: status,
      tools: const <String>[],
      createdAt: DateTime.utc(2026, 9, 17),
    );

TeamTask _task(String id, TeamTaskStatus status) => TeamTask(
      id: id,
      description: '任务$id',
      status: status,
      dependsOn: const <String>[],
      version: 1,
      createdAt: DateTime.utc(2026, 9, 17),
    );

Future<void> _flush() async {
  // 让 broadcast 流的事件派发完成（microtask 队列）。
  for (int i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('构造时从团队当前状态建初始快照', () {
    final FakeAgentTeam team = FakeAgentTeam()
      ..addMember(_mate('a', TeammateStatus.working));
    final TeamSubscription sub = TeamSubscription(
      team: team,
      onChanged: (TeamSnapshot _) {},
    );
    expect(sub.snapshot.members.single.name, 'a');
    expect(sub.snapshot.hasTeam, isTrue);
    sub.dispose();
  });

  test('成员/任务事件驱动快照重建并回调', () async {
    final FakeAgentTeam team = FakeAgentTeam();
    final List<TeamSnapshot> seen = <TeamSnapshot>[];
    final TeamSubscription sub = TeamSubscription(
      team: team,
      onChanged: seen.add,
    );

    team
      ..addMember(_mate('a', TeammateStatus.working))
      ..emit(TeammateSpawned(_mate('a', TeammateStatus.working)));
    await _flush();
    team
      ..addMember(_mate('a', TeammateStatus.done))
      ..emit(TeammateStatusChanged(_mate('a', TeammateStatus.done)));
    await _flush();
    team
      ..addTask(_task('t1', TeamTaskStatus.done))
      ..emit(TeamTaskCreated(_task('t1', TeamTaskStatus.done)));
    await _flush();
    team
      ..addTask(_task('t1', TeamTaskStatus.claimed))
      ..emit(TeamTaskChanged(_task('t1', TeamTaskStatus.claimed)));
    await _flush();

    expect(seen, hasLength(4));
    expect(seen.last.members.single.status, TeammateStatus.done);
    expect(seen.last.tasks.single.status, TeamTaskStatus.claimed);
    expect(seen.last.activeMembers, 0);
    sub.dispose();
  });

  test('TeamMessageSent 不驱动重绘', () {
    final FakeAgentTeam team = FakeAgentTeam();
    int calls = 0;
    final TeamSubscription sub = TeamSubscription(
      team: team,
      onChanged: (TeamSnapshot _) => calls++,
    );
    team.emit(const TeamMessageSent('a', 'b', '内部消息'));
    expect(calls, 0);
    sub.dispose();
  });

  test('costSource 注入后快照带成本', () {
    final FakeAgentTeam team = FakeAgentTeam();
    final TeamSubscription sub = TeamSubscription(
      team: team,
      costSource: const _FixedCost(3.25),
      onChanged: (TeamSnapshot _) {},
    );
    expect(sub.snapshot.totalCost, 3.25);
    sub.dispose();
  });

  test('dispose 后事件不再回调', () {
    final FakeAgentTeam team = FakeAgentTeam();
    int calls = 0;
    final TeamSubscription sub = TeamSubscription(
      team: team,
      onChanged: (TeamSnapshot _) => calls++,
    );
    sub.dispose();
    team
      ..addMember(_mate('a', TeammateStatus.working))
      ..emit(TeammateSpawned(_mate('a', TeammateStatus.working)));
    expect(calls, 0);
  });
}

class _FixedCost implements TeamCostSource {
  const _FixedCost(this.totalCost);
  @override
  final double totalCost;
}
