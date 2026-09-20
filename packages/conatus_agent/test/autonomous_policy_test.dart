import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

void main() {
  group('TimeWindow', () {
    DateTime at(int hour, [int minute = 0]) =>
        DateTime(2026, 9, 20, hour, minute);

    test('普通窗口：界内 true，界外 false，端点含', () {
      final TimeWindow window = TimeWindow(
        start: const Duration(hours: 9),
        end: const Duration(hours: 18),
      );
      expect(window.contains(at(8, 59)), isFalse);
      expect(window.contains(at(9)), isTrue);
      expect(window.contains(at(12)), isTrue);
      expect(window.contains(at(18)), isTrue);
      expect(window.contains(at(18, 1)), isFalse);
    });

    test('跨午夜窗口（22:00-06:00）', () {
      final TimeWindow window = TimeWindow(
        start: const Duration(hours: 22),
        end: const Duration(hours: 6),
      );
      expect(window.contains(at(21, 59)), isFalse);
      expect(window.contains(at(22)), isTrue);
      expect(window.contains(at(23)), isTrue);
      expect(window.contains(at(0)), isTrue);
      expect(window.contains(at(6)), isTrue);
      expect(window.contains(at(6, 1)), isFalse);
    });

    test('nextStart：窗口未开始 → 今天 start', () {
      final TimeWindow window = TimeWindow(
        start: const Duration(hours: 9),
        end: const Duration(hours: 18),
      );
      expect(window.nextStart(at(8)), DateTime(2026, 9, 20, 9));
    });

    test('nextStart：普通窗口内 → 明天 start', () {
      final TimeWindow window = TimeWindow(
        start: const Duration(hours: 9),
        end: const Duration(hours: 18),
      );
      expect(window.nextStart(at(12)), DateTime(2026, 9, 21, 9));
    });

    test('nextStart：跨午夜窗口内 → 下一次开始', () {
      final TimeWindow window = TimeWindow(
        start: const Duration(hours: 22),
        end: const Duration(hours: 6),
      );
      expect(window.nextStart(at(23)), DateTime(2026, 9, 21, 22));
      expect(window.nextStart(at(2)), DateTime(2026, 9, 20, 22));
    });

    test('构造断言：start 必须是一天内时刻，end 小于 48 小时', () {
      expect(
        () => TimeWindow(
          start: const Duration(hours: 24),
          end: const Duration(hours: 6),
        ),
        throwsArgumentError,
      );
      expect(
        () => TimeWindow(
          start: const Duration(hours: 6),
          end: const Duration(hours: 48),
        ),
        throwsArgumentError,
      );
    });
  });

  group('DefaultAutonomousPolicy', () {
    test('缺省值：无预算限制 / 全天 / 8 轮 / 5 分钟 / 不强制人在环', () {
      const DefaultAutonomousPolicy policy = DefaultAutonomousPolicy();
      expect(policy.dailyBudget, double.infinity);
      expect(policy.activeWindow, isNull);
      expect(policy.allowedActions, isEmpty);
      expect(policy.requireApproval, isEmpty);
      expect(policy.maxContinuousRounds, 8);
      expect(policy.maxTurnDuration, const Duration(minutes: 5));
      expect(policy.requireHumanInLoop, isFalse);
    });

    test('firstViolation：黑名单命中优先，白名单外越界，空白名单不限制', () {
      const DefaultAutonomousPolicy policy = DefaultAutonomousPolicy(
        allowedActions: <String>{'safe_tool'},
        requireApproval: <String>{'danger_tool'},
      );
      expect(policy.firstViolation(const <AgentStep>[]), isNull);
      expect(
        policy.firstViolation(<AgentStep>[
          AgentStep(call: _call('safe_tool'), result: _ok()),
        ]),
        isNull,
      );
      expect(
        policy.firstViolation(<AgentStep>[
          AgentStep(call: _call('rogue_tool'), result: _ok()),
        ]),
        'rogue_tool',
      );
      expect(
        policy.firstViolation(<AgentStep>[
          AgentStep(call: _call('danger_tool'), result: _ok()),
        ]),
        'danger_tool',
      );
      const DefaultAutonomousPolicy open = DefaultAutonomousPolicy();
      expect(
        open.firstViolation(<AgentStep>[
          AgentStep(call: _call('anything'), result: _ok()),
        ]),
        isNull,
      );
    });
  });
}

LlmToolCall _call(String name) => LlmToolCall(id: 'c1', name: name);

ToolResult _ok() => ToolResult.success('ok');
