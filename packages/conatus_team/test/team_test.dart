import 'package:conatus_team/conatus_team.dart';
import 'package:test/test.dart';

void main() {
  group('Teammate', () {
    final Teammate base = Teammate(
      id: 't1',
      name: 'security-reviewer',
      role: TeamRole.member,
      status: TeammateStatus.idle,
      tools: <String>['read', 'search'],
      createdAt: DateTime.utc(2026, 9, 17),
      systemPrompt: 'You review code for security issues.',
      currentTaskId: 'task-1',
    );

    test('copyWith 保持不可变性；currentTaskId 传 null 表示清除', () {
      final Teammate working = base.copyWith(status: TeammateStatus.working);
      expect(base.status, TeammateStatus.idle);
      expect(base.currentTaskId, 'task-1');
      expect(working.status, TeammateStatus.working);
      expect(working.currentTaskId, 'task-1');
      expect(working.id, base.id);

      final Teammate cleared = working.copyWith(currentTaskId: null);
      expect(cleared.currentTaskId, isNull);
      expect(working.currentTaskId, 'task-1');
    });

    test('fromJson / toJson 往返一致', () {
      final Teammate roundTripped =
          Teammate.fromJson(Map<String, Object?>.from(base.toJson()));
      expect(roundTripped.id, base.id);
      expect(roundTripped.name, base.name);
      expect(roundTripped.role, base.role);
      expect(roundTripped.status, base.status);
      expect(roundTripped.tools, equals(base.tools));
      expect(roundTripped.createdAt, base.createdAt);
      expect(roundTripped.systemPrompt, base.systemPrompt);
      expect(roundTripped.currentTaskId, base.currentTaskId);
    });

    test('fromJson 对未知枚举降级为默认值', () {
      final Teammate fallback = Teammate.fromJson(<String, Object?>{
        'id': 'x',
        'name': 'x',
        'role': 'unknown',
        'status': 'unknown',
        'tools': <Object>[],
        'createdAt': DateTime.utc(2026).toIso8601String(),
      });
      expect(fallback.role, TeamRole.member);
      expect(fallback.status, TeammateStatus.idle);
    });

    test('isTerminal 对 done / failed 为 true', () {
      expect(base.isTerminal, isFalse);
      expect(
        base.copyWith(status: TeammateStatus.done).isTerminal,
        isTrue,
      );
      expect(
        base.copyWith(status: TeammateStatus.failed).isTerminal,
        isTrue,
      );
    });

    test('状态机转换：idle → working → done / failed（终态）', () {
      final Teammate working = base.copyWith(status: TeammateStatus.working);
      final Teammate done = working.copyWith(status: TeammateStatus.done);
      expect(done.isTerminal, isTrue);
      final Teammate failed = working.copyWith(status: TeammateStatus.failed);
      expect(failed.isTerminal, isTrue);
      // 终态再做 copyWith 不影响源（类型层不变性；状态机约束由实现层守）
      final Teammate reopened = done.copyWith(status: TeammateStatus.idle);
      expect(done.isTerminal, isTrue);
      expect(reopened.isTerminal, isFalse);
    });

    test('状态机转换：working → waiting → working', () {
      final Teammate waiting = base.copyWith(status: TeammateStatus.waiting);
      expect(waiting.isTerminal, isFalse);
      final Teammate resumed = waiting.copyWith(status: TeammateStatus.working);
      expect(resumed.status, TeammateStatus.working);
    });

    test('TeammateStatus 六个值齐全', () {
      expect(TeammateStatus.values, hasLength(6));
      expect(TeammateStatus.values, contains(TeammateStatus.idle));
      expect(TeammateStatus.values, contains(TeammateStatus.working));
      expect(TeammateStatus.values, contains(TeammateStatus.waiting));
      expect(TeammateStatus.values, contains(TeammateStatus.finished));
      expect(TeammateStatus.values, contains(TeammateStatus.done));
      expect(TeammateStatus.values, contains(TeammateStatus.failed));
    });

    test('finished 非终态，可再接新任务', () {
      final Teammate finished =
          base.copyWith(status: TeammateStatus.finished);
      expect(finished.isTerminal, isFalse);
      expect(
        finished.copyWith(status: TeammateStatus.working).status,
        TeammateStatus.working,
      );
    });
  });

  group('TeamTask', () {
    final TeamTask base = TeamTask(
      id: 'task-1',
      description: '审查 lib/foo.dart',
      status: TeamTaskStatus.pending,
      dependsOn: <String>['task-0'],
      version: 3,
      createdAt: DateTime.utc(2026, 9, 17),
    );

    test('copyWith 保持不可变性；version 不传则保留', () {
      final TeamTask claimed = base.copyWith(
        status: TeamTaskStatus.claimed,
        assigneeId: 't1',
      );
      expect(base.status, TeamTaskStatus.pending);
      expect(base.assigneeId, isNull);
      expect(claimed.status, TeamTaskStatus.claimed);
      expect(claimed.assigneeId, 't1');
      expect(claimed.version, 3);

      final TeamTask withBump = claimed.copyWith(
        status: TeamTaskStatus.done,
        version: claimed.version + 1,
        result: 'LGTM',
      );
      expect(withBump.version, 4);
      expect(withBump.result, 'LGTM');
      expect(claimed.result, isNull);
    });

    test('assigneeId / result / error 传 null 表示清除', () {
      final TeamTask claimed = base.copyWith(
        status: TeamTaskStatus.claimed,
        assigneeId: 't1',
        result: 'r',
        error: 'e',
      );
      final TeamTask released = claimed.copyWith(
        status: TeamTaskStatus.pending,
        assigneeId: null,
        result: null,
        error: null,
      );
      expect(released.assigneeId, isNull);
      expect(released.result, isNull);
      expect(released.error, isNull);
      expect(claimed.assigneeId, 't1');
      expect(claimed.result, 'r');
      expect(claimed.error, 'e');
    });

    test('fromJson / toJson 往返一致', () {
      final TeamTask rich = base.copyWith(
        assigneeId: 't1',
        result: <String, Object?>{'ok': true},
        error: 'oops',
      );
      final TeamTask roundTripped =
          TeamTask.fromJson(Map<String, Object?>.from(rich.toJson()));
      expect(roundTripped.id, rich.id);
      expect(roundTripped.description, rich.description);
      expect(roundTripped.status, rich.status);
      expect(roundTripped.assigneeId, rich.assigneeId);
      expect(roundTripped.dependsOn, equals(rich.dependsOn));
      expect(roundTripped.version, rich.version);
      expect(roundTripped.createdAt, rich.createdAt);
      expect(roundTripped.result, equals(rich.result));
      expect(roundTripped.error, 'oops');
    });

    test('fromJson 对未知状态降级为 pending', () {
      final TeamTask fallback = TeamTask.fromJson(<String, Object?>{
        'id': 'x',
        'description': 'x',
        'status': 'unknown',
        'dependsOn': <Object>[],
        'version': 0,
        'createdAt': DateTime.utc(2026).toIso8601String(),
      });
      expect(fallback.status, TeamTaskStatus.pending);
    });

    test('isTerminal 对 done / failed 为 true', () {
      expect(base.isTerminal, isFalse);
      expect(
        base.copyWith(status: TeamTaskStatus.done).isTerminal,
        isTrue,
      );
      expect(
        base.copyWith(status: TeamTaskStatus.failed).isTerminal,
        isTrue,
      );
    });

    test('状态机转换：pending → claimed → done / failed（终态）', () {
      final TeamTask claimed = base.copyWith(
        status: TeamTaskStatus.claimed,
        assigneeId: 't1',
      );
      expect(claimed.isTerminal, isFalse);
      expect(
        claimed.copyWith(status: TeamTaskStatus.done).isTerminal,
        isTrue,
      );
      expect(
        claimed.copyWith(status: TeamTaskStatus.failed).isTerminal,
        isTrue,
      );
    });

    test('状态机转换：claimed → released（回 pending，assigneeId 清空）', () {
      final TeamTask claimed = base.copyWith(
        status: TeamTaskStatus.claimed,
        assigneeId: 't1',
      );
      final TeamTask released = claimed.copyWith(
        status: TeamTaskStatus.pending,
        assigneeId: null,
      );
      expect(released.status, TeamTaskStatus.pending);
      expect(released.assigneeId, isNull);
    });

    test('TeamTaskStatus 四个值齐全', () {
      expect(TeamTaskStatus.values, hasLength(4));
      expect(TeamTaskStatus.values, contains(TeamTaskStatus.pending));
      expect(TeamTaskStatus.values, contains(TeamTaskStatus.claimed));
      expect(TeamTaskStatus.values, contains(TeamTaskStatus.done));
      expect(TeamTaskStatus.values, contains(TeamTaskStatus.failed));
    });
  });

  group('TeamException', () {
    test('code + message + toString', () {
      const TeamException exc = TeamException('version-mismatch', '版本不符');
      expect(exc.code, 'version-mismatch');
      expect(exc.message, '版本不符');
      expect(exc.toString(), 'TeamException(version-mismatch): 版本不符');
    });
  });

  group('AgentTeamEvent', () {
    test('子类携带字段；sealed 基类不可直接实例化', () {
      final Teammate t = Teammate(
        id: 't1',
        name: 'x',
        role: TeamRole.member,
        status: TeammateStatus.idle,
        tools: <String>[],
        createdAt: DateTime.utc(2026),
      );
      final TeamTask task = TeamTask(
        id: 'tk1',
        description: 'd',
        status: TeamTaskStatus.pending,
        dependsOn: <String>[],
        version: 0,
        createdAt: DateTime.utc(2026),
      );

      expect(TeammateSpawned(t).teammate, same(t));
      expect(TeammateStatusChanged(t).teammate, same(t));
      expect(TeamTaskCreated(task).task, same(task));
      expect(TeamTaskChanged(task).task, same(task));

      const TeamMessageSent msg = TeamMessageSent('a', 'b', 'hi');
      expect(msg.from, 'a');
      expect(msg.to, 'b');
      expect(msg.message, 'hi');
    });

    test('sealed 子类层级穷尽：每种事件可独立识别', () {
      final List<AgentTeamEvent> events = <AgentTeamEvent>[
        TeammateSpawned(Teammate(
          id: '1',
          name: 'a',
          role: TeamRole.lead,
          status: TeammateStatus.idle,
          tools: <String>[],
          createdAt: DateTime.utc(2026),
        )),
        TeammateStatusChanged(Teammate(
          id: '2',
          name: 'b',
          role: TeamRole.member,
          status: TeammateStatus.working,
          tools: <String>[],
          createdAt: DateTime.utc(2026),
        )),
        TeamTaskCreated(TeamTask(
          id: 'tk1',
          description: 'd',
          status: TeamTaskStatus.pending,
          dependsOn: <String>[],
          version: 0,
          createdAt: DateTime.utc(2026),
        )),
        TeamTaskChanged(TeamTask(
          id: 'tk2',
          description: 'd',
          status: TeamTaskStatus.claimed,
          dependsOn: <String>[],
          version: 1,
          createdAt: DateTime.utc(2026),
        )),
        const TeamMessageSent('a', 'b', 'hi'),
      ];

      int spawned = 0, statusChanged = 0, created = 0, changed = 0, sent = 0;
      for (final AgentTeamEvent e in events) {
        switch (e) {
          case TeammateSpawned():
            spawned++;
          case TeammateStatusChanged():
            statusChanged++;
          case TeamTaskCreated():
            created++;
          case TeamTaskChanged():
            changed++;
          case TeamMessageSent():
            sent++;
        }
      }
      expect(spawned, 1);
      expect(statusChanged, 1);
      expect(created, 1);
      expect(changed, 1);
      expect(sent, 1);
    });
  });
}
