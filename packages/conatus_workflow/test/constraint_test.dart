import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_workflow/conatus_workflow.dart';
import 'package:test/test.dart';

class _FakeCostTracker implements CostTracker {
  _FakeCostTracker(this.todayCost);

  @override
  final double todayCost;
}

void main() {
  group('BudgetConstraint', () {
    test('无成本跟踪时放行', () async {
      const constraint = BudgetConstraint(dailyMax: 10);
      expect(await constraint.check(_ctx()), isNull);
    });

    test('当日成本未超限放行', () async {
      final constraint = BudgetConstraint(
        dailyMax: 10,
        costTracker: _FakeCostTracker(5),
      );
      expect(await constraint.check(_ctx()), isNull);
    });

    test('当日成本超限返回原因', () async {
      final constraint = BudgetConstraint(
        dailyMax: 10,
        costTracker: _FakeCostTracker(15),
      );
      final reason = await constraint.check(_ctx());
      expect(reason, contains('预算超限'));
    });
  });

  group('TimeWindowConstraint', () {
    final window =
        TimeWindow(start: const Duration(hours: 9), end: const Duration(hours: 18));

    test('窗口内放行', () async {
      final constraint = TimeWindowConstraint(window);
      final result =
          await constraint.check(_ctx(now: () => DateTime(2026, 1, 1, 10)));
      expect(result, isNull);
    });

    test('窗口外返回原因', () async {
      final constraint = TimeWindowConstraint(window);
      final reason =
          await constraint.check(_ctx(now: () => DateTime(2026, 1, 1, 20)));
      expect(reason, contains('时间窗口'));
    });
  });

  group('PermissionConstraint', () {
    test('权限体系未启用时放行', () async {
      const constraint = PermissionConstraint(requiredPermissions: {'admin'});
      expect(await constraint.check(_ctx()), isNull);
    });

    test('缺少权限返回原因', () async {
      const constraint =
          PermissionConstraint(requiredPermissions: {'admin', 'ops'});
      final reason = await constraint.check(_ctx(permissions: {'ops'}));
      expect(reason, contains('缺少权限'));
    });

    test('权限齐备放行', () async {
      const constraint = PermissionConstraint(requiredPermissions: {'admin'});
      final result = await constraint.check(_ctx(permissions: {'admin'}));
      expect(result, isNull);
    });
  });

  group('MutexConstraint', () {
    test('互斥占用中返回原因', () async {
      const constraint = MutexConstraint('nightly');
      final reason = await constraint.check(_ctx(runningMutexes: {'nightly'}));
      expect(reason, contains('互斥'));
    });

    test('互斥空闲放行', () async {
      const constraint = MutexConstraint('nightly');
      expect(await constraint.check(_ctx()), isNull);
    });
  });
}

ConstraintContext _ctx({
  DateTime Function()? now,
  Set<String>? permissions,
  Set<String> runningMutexes = const {},
}) =>
    ConstraintContext(
      now: now ?? DateTime.now,
      permissions: permissions,
      runningMutexes: runningMutexes,
    );
