import 'package:conatus_agent/conatus_agent.dart';
import 'package:test/test.dart';

void main() {
  final PriorityEngine engine = PriorityEngine();

  Goal goalWith(int round, int maxRounds, {String id = 'g'}) => Goal(
        id: id,
        text: 't',
        status: GoalStatus.active,
        round: round,
        maxRounds: maxRounds,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

  group('GoalPriority', () {
    test('score 公式：importance*0.5 + urgency*0.3 + (1-progress)*0.2', () {
      final GoalPriority priority = GoalPriority(
        goal: goalWith(1, 4),
        importance: 8,
        urgency: 6,
        progress: 0.25,
      );
      expect(priority.score, closeTo(5.95, 1e-9));
    });
  });

  group('PriorityEngine', () {
    test('progress 由 round/maxRounds 推导；importance/urgency 缺省 5', () {
      final GoalPriority score = engine.scoreOf(goalWith(1, 4));
      expect(score.importance, 5);
      expect(score.urgency, 5);
      expect(score.progress, closeTo(0.25, 1e-9));
    });

    test('importance/urgency 可按 id 覆盖', () {
      final GoalPriority score = engine.scoreOf(
        goalWith(1, 4, id: 'g1'),
        importance: <String, int>{'g1': 9},
        urgency: <String, int>{'g1': 3},
      );
      expect(score.importance, 9);
      expect(score.urgency, 3);
    });

    test('selectNext 选最高分', () {
      final Goal low = goalWith(0, 10, id: 'low');
      final Goal high = goalWith(0, 10, id: 'high');
      final Goal? picked = engine.selectNext(
        <Goal>[low, high],
        importance: <String, int>{'low': 1, 'high': 10},
      );
      expect(picked, high);
    });

    test('selectNext 同分保持原序', () {
      final Goal first = goalWith(0, 10, id: 'first');
      final Goal second = goalWith(0, 10, id: 'second');
      expect(engine.selectNext(<Goal>[first, second]), first);
    });

    test('selectNext 空列表返回 null', () {
      expect(engine.selectNext(<Goal>[]), isNull);
    });
  });
}
