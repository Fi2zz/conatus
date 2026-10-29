import 'package:conatus_agent/conatus_agent.dart';
import 'package:test/test.dart';

const ToolBudgetPolicy _policy = ToolBudgetPolicy(
  economyAfter: 2,
  strictAfter: 4,
  finalizeAfter: 6,
  strictEvery: 2,
);

void main() {
  test('阶段边界：经济 → 收敛 → 收口', () {
    expect(_policy.stageOf(1), ToolBudgetStage.normal);
    expect(_policy.stageOf(2), ToolBudgetStage.economy);
    expect(_policy.stageOf(3), ToolBudgetStage.economy);
    expect(_policy.stageOf(4), ToolBudgetStage.strict);
    expect(_policy.stageOf(6), ToolBudgetStage.strict);
    expect(_policy.stageOf(7), ToolBudgetStage.finalize);
  });

  test('经济阶段只在边界提醒一次，收敛阶段按间隔重复', () {
    expect(_policy.note(2), contains('经济'));
    expect(_policy.note(3), isNull);
    expect(_policy.note(4), contains('收敛'));
    expect(_policy.note(5), isNull);
    expect(_policy.note(6), contains('收敛'));
    expect(_policy.note(8), contains('收敛'));
  });

  test('收口只拒非白名单工具', () {
    expect(_policy.denialFor(7, 'read'), isNull);
    expect(_policy.denialFor(7, 'bash'), contains('预算'));
    expect(_policy.denialFor(7, 'bash'), contains('收口'));
    expect(_policy.denialFor(6, 'bash'), isNull);
  });

  test('finalizeAfter 为 0 表示不限', () {
    const ToolBudgetPolicy unlimited = ToolBudgetPolicy(finalizeAfter: 0);

    expect(unlimited.stageOf(1000), ToolBudgetStage.strict);
    expect(unlimited.denialFor(1000, 'bash'), isNull);
  });

  test('阶段阈值设为 0 即关闭该阶段', () {
    const ToolBudgetPolicy off = ToolBudgetPolicy(
      economyAfter: 0,
      strictAfter: 0,
      finalizeAfter: 0,
    );

    expect(off.stageOf(100), ToolBudgetStage.normal);
    expect(off.note(100), isNull);
    expect(off.denialFor(100, 'bash'), isNull);
  });

  test('strictEvery 为 0 时只在边界提醒一次', () {
    const ToolBudgetPolicy once =
        ToolBudgetPolicy(strictAfter: 3, strictEvery: 0);

    expect(once.note(3), contains('收敛'));
    expect(once.note(4), isNull);
  });

  test('默认策略的收口白名单含只读工具', () {
    const ToolBudgetPolicy defaults = ToolBudgetPolicy();

    expect(defaults.denialFor(45, 'read'), isNull);
    expect(defaults.denialFor(45, 'bash'), isNotNull);
    expect(defaults.stageOf(44), ToolBudgetStage.strict);
    expect(defaults.stageOf(45), ToolBudgetStage.finalize);
  });
}
