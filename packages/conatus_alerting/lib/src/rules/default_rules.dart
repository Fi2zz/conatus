/// 默认规则集：开箱即用的异常检测（handoff-11 第 6 节）。
library;

import '../alert.dart';
import '../rule.dart';

/// 一组开箱即用的规则。
///
/// 事件名对齐 conatus 的实际遥测词汇（`conatus_agent` 的 `telemetry.dart`）：
/// `llm.request`（含 `durationMs`）、`tool.called` / `tool.failed`（含
/// `durationMs`）、`agent.round`（含 `step`）。`cost.recorded` /
/// `agent.round.exceeded` 为预留事件名，由上层埋点触发。
List<AlertRule> defaultAlertRules() => <AlertRule>[
      AlertRule(
        name: 'llm-slow',
        severity: AlertSeverity.warning,
        description: 'LLM 调用超过 30 秒',
        condition: (event, ctx) =>
            event.name == 'llm.request' &&
            (event.data['durationMs'] as int? ?? 0) > 30000,
      ),
      AlertRule(
        name: 'llm-very-slow',
        severity: AlertSeverity.critical,
        description: 'LLM 调用超过 60 秒',
        condition: (event, ctx) =>
            event.name == 'llm.request' &&
            (event.data['durationMs'] as int? ?? 0) > 60000,
        cooldown: const Duration(minutes: 10),
      ),
      AlertRule(
        name: 'tool-slow',
        severity: AlertSeverity.warning,
        description: '工具调用超过 10 秒',
        condition: (event, ctx) =>
            event.name == 'tool.called' &&
            (event.data['durationMs'] as int? ?? 0) > 10000,
      ),
      AlertRule(
        name: 'tool-failures',
        severity: AlertSeverity.critical,
        description: '1 分钟内工具失败超过 5 次',
        condition: (event, ctx) {
          if (event.name != 'tool.failed') return false;
          ctx.record('tool.failed');
          return ctx.countInWindow('tool.failed', const Duration(minutes: 1)) > 5;
        },
      ),
      AlertRule(
        name: 'session-budget',
        severity: AlertSeverity.warning,
        description: 'Session 成本超过 1 美元',
        condition: (event, ctx) =>
            event.name == 'cost.recorded' &&
            (event.data['sessionCost'] as double? ?? 0) > 1.0,
        cooldown: const Duration(minutes: 30),
      ),
      AlertRule(
        name: 'daily-budget',
        severity: AlertSeverity.critical,
        description: '当日成本超过 10 美元',
        condition: (event, ctx) =>
            event.name == 'cost.recorded' &&
            (event.data['dailyCost'] as double? ?? 0) > 10.0,
        cooldown: const Duration(hours: 1),
      ),
      AlertRule(
        name: 'agent-loop',
        severity: AlertSeverity.warning,
        description: 'Agent 轮次超过 20 步',
        condition: (event, ctx) =>
            event.name == 'agent.round.exceeded' ||
            (event.name == 'agent.round' &&
                (event.data['step'] as int? ?? 0) > 20),
      ),
      AlertRule(
        name: 'subagent-stuck',
        severity: AlertSeverity.warning,
        description: '子 Agent 运行超过 5 分钟',
        // 暂缓：事件只记录不触发，实际超时判断由上层定时器完成。
        condition: (event, ctx) {
          if (event.name != 'subagent.spawned') return false;
          ctx.record('subagent.${event.data['id']}');
          return false;
        },
      ),
    ];
