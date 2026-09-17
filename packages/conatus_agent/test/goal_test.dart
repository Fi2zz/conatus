import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  group('Goal 类型', () {
    final Goal base = Goal(
      id: 'g1',
      text: '盯机票',
      status: GoalStatus.active,
      round: 2,
      maxRounds: 256,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026, 2),
      revisions: <GoalRevision>[
        GoalRevision(text: '盯机票', revisedAt: DateTime.utc(2026)),
      ],
    );

    test('copyWith 保持不可变；blockReason 传 null 表示清除', () {
      final Goal blocked = base.copyWith(
        status: GoalStatus.blocked,
        blockReason: '需要授权',
        updatedAt: DateTime.utc(2026, 3),
      );
      expect(base.status, GoalStatus.active);
      expect(base.blockReason, isNull);
      expect(blocked.blockReason, '需要授权');

      final Goal resumed = blocked.copyWith(
        status: GoalStatus.active,
        blockReason: null,
      );
      expect(resumed.blockReason, isNull);
      expect(resumed.round, 2);
      expect(resumed.maxRounds, 256);
      expect(resumed.id, 'g1');
    });

    test('fromJson / toJson 往返一致', () {
      final Goal rich = base.copyWith(blockReason: 'x');
      final Goal roundTripped =
          Goal.fromJson(Map<String, Object?>.from(rich.toJson()));
      expect(roundTripped.id, rich.id);
      expect(roundTripped.text, rich.text);
      expect(roundTripped.status, rich.status);
      expect(roundTripped.round, rich.round);
      expect(roundTripped.maxRounds, rich.maxRounds);
      expect(roundTripped.createdAt, rich.createdAt);
      expect(roundTripped.updatedAt, rich.updatedAt);
      expect(roundTripped.blockReason, rich.blockReason);
      expect(roundTripped.revisions, hasLength(1));
      expect(roundTripped.revisions.single.text, '盯机票');
      expect(roundTripped.revisions.single.revisedAt, DateTime.utc(2026));
    });

    test('isTerminal / isAdvanceable', () {
      expect(base.isTerminal, isFalse);
      expect(base.isAdvanceable, isTrue);
      expect(
        base.copyWith(status: GoalStatus.completed).isTerminal,
        isTrue,
      );
      expect(
        base.copyWith(status: GoalStatus.cleared).isAdvanceable,
        isFalse,
      );
      expect(
        base.copyWith(status: GoalStatus.blocked).isAdvanceable,
        isFalse,
      );
    });
  });

  group('restoreGoalState', () {
    test('无事件返回 null；折叠最后一条；cleared 视为无目标', () {
      final Session session = Session(id: 's1');
      expect(restoreGoalState(session), isNull);

      final Goal goal = Goal(
        id: 'g1',
        text: '盯机票',
        status: GoalStatus.active,
        round: 0,
        maxRounds: 256,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      session.append(kGoalEvent, data: goal.toJson());
      expect(restoreGoalState(session)!.text, '盯机票');

      session.append(kGoalEvent,
          data: goal.copyWith(status: GoalStatus.cleared).toJson());
      expect(restoreGoalState(session), isNull);
    });

    test('fork 出的会话不继承目标', () {
      final Session parent = Session(id: 'p');
      final Goal goal = Goal(
        id: 'g1',
        text: '盯机票',
        status: GoalStatus.active,
        round: 0,
        maxRounds: 256,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      parent.append(kGoalEvent, data: goal.toJson());
      final Session child = parent.fork();

      expect(restoreGoalState(parent)!.text, '盯机票');
      expect(restoreGoalState(child), isNull);
    });
  });

  group('DefaultGoalService 状态机', () {
    test('create 初始 active，写 goal/changed 并广播', () async {
      final Session session = Session(id: 's1');
      final DefaultGoalService service = DefaultGoalService(session: session);
      final List<Goal> emitted = <Goal>[];
      final StreamSubscription<Goal> sub = service.changes.listen(emitted.add);

      final Goal goal = await service.create('盯机票', maxRounds: 4);

      expect(goal.status, GoalStatus.active);
      expect(goal.round, 0);
      expect(goal.maxRounds, 4);
      expect(goal.revisions, hasLength(1));
      expect(service.current!.id, goal.id);
      expect(
        session.events.where((SessionEvent e) => e.type == kGoalEvent),
        hasLength(1),
      );
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(emitted, hasLength(1));
    });

    test('已有非终态目标时 create 抛 already_exists；终态不阻挡', () async {
      final DefaultGoalService service = DefaultGoalService();
      await service.create('A');
      expect(
        () => service.create('B'),
        throwsA(isA<GoalException>()
            .having((GoalException e) => e.code, 'code', 'already_exists')),
      );

      await service.complete();
      final Goal second = await service.create('B');
      expect(second.text, 'B');
    });

    test('edit 仅 active / paused 可编辑并追加修订', () async {
      final DefaultGoalService service = DefaultGoalService();
      await service.create('盯机票');

      final Goal edited = await service.edit('盯明天北京机票');
      expect(edited.text, '盯明天北京机票');
      expect(edited.revisions, hasLength(2));
      expect(edited.revisions.first.text, '盯机票');

      await service.pause();
      expect((await service.edit('暂停中改')).revisions, hasLength(3));

      await service.resume();
      await service.block('卡住');
      expect(
          () => service.edit('x'),
          throwsA(isA<GoalException>()
              .having((GoalException e) => e.code, 'code', 'invalid_status')));
    });

    test('pause / resume / block 转换与非法转换', () async {
      final DefaultGoalService service = DefaultGoalService();
      expect(service.pause, throwsA(isA<GoalException>()));

      await service.create('g');
      await service.pause();
      expect(service.current!.status, GoalStatus.paused);
      expect(service.pause, throwsA(isA<GoalException>()));

      await service.resume();
      expect(service.current!.status, GoalStatus.active);
      expect(service.resume, throwsA(isA<GoalException>()));

      final Goal blocked = await service.block('需要授权');
      expect(blocked.blockReason, '需要授权');
      final Goal resumed = await service.resume();
      expect(resumed.status, GoalStatus.active);
      expect(resumed.blockReason, isNull);
    });

    test('complete 置终态；clear 后 current 为 null 且可再创建', () async {
      final DefaultGoalService service = DefaultGoalService();
      await service.create('g');
      final Goal done = await service.complete();
      expect(done.status, GoalStatus.completed);
      expect(service.current!.status, GoalStatus.completed);
      expect(() => service.edit('x'), throwsA(isA<GoalException>()));

      final Goal cleared = await service.clear();
      expect(cleared.status, GoalStatus.cleared);
      expect(service.current, isNull);
      expect(await service.create('新目标'), isNotNull);
    });

    test('advanceRound 递增；达到上限自动 block', () async {
      final DefaultGoalService service = DefaultGoalService();
      await service.create('g', maxRounds: 2);

      await service.advanceRound();
      expect(service.current!.round, 1);

      await service.advanceRound();
      final Goal goal = service.current!;
      expect(goal.status, GoalStatus.blocked);
      expect(goal.round, 2);
      expect(goal.blockReason, kGoalRoundLimitReason);

      expect(service.advanceRound, throwsA(isA<GoalException>()));
    });

    test('构造时从 session 恢复目标状态', () async {
      final Session session = Session(id: 's1');
      final DefaultGoalService first = DefaultGoalService(session: session);
      await first.create('盯机票', maxRounds: 8);
      await first.pause();

      final DefaultGoalService restored = DefaultGoalService(session: session);
      expect(restored.current!.text, '盯机票');
      expect(restored.current!.status, GoalStatus.paused);
      expect(restored.current!.maxRounds, 8);
    });

    test('dispose 幂等；dispose 后不再持久化', () async {
      final Session session = Session(id: 's1');
      final DefaultGoalService service = DefaultGoalService(session: session);
      await service.create('g');
      service.dispose();
      service.dispose();
      expect(() async => service.pause(), returnsNormally);
      expect(
        session.events.where((SessionEvent e) => e.type == kGoalEvent),
        hasLength(1),
      );
    });
  });
}
