/// 流程自动化的词汇：触发器与自动化定义。
///
/// 触发器是**数据**：声明式定义，不从代码硬编码。条件触发复用
/// alerting 的 [AlertRule] 类型（条件 + 冷却语义），把「通知」替换为
/// 「启动 workflow」。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_alerting/conatus_alerting.dart';

import 'constraint.dart';
import 'post_action.dart';

/// 触发器。
sealed class Trigger {
  const Trigger();
}

/// 定时触发。表达式同 conatus_cron（cron / at / every / daily 规则）。
class CronTrigger extends Trigger {
  const CronTrigger(this.expression);

  final String expression;
}

/// 事件触发。监听遥测事件流，事件名匹配且 [filter] 通过时触发。
class EventTrigger extends Trigger {
  const EventTrigger(this.eventName, {this.filter});

  final String eventName;
  final bool Function(TelemetryEvent)? filter;
}

/// 条件触发。复用 alerting 的规则类型：条件成立且不在冷却期时触发。
class ConditionTrigger extends Trigger {
  const ConditionTrigger(this.rule);

  final AlertRule rule;
}

/// 手动触发。只经 [WorkflowScheduler.trigger] 启动。
class ManualTrigger extends Trigger {
  const ManualTrigger();
}

/// 一个流程自动化 = 触发器 + 流程 + 运行策略 + 后处理。
class Automation {
  const Automation({
    required this.name,
    required this.trigger,
    required this.workflowName,
    this.inputs = const <String, Object?>{},
    this.constraints = const <Constraint>[],
    this.onComplete,
    this.cooldown = Duration.zero,
  });

  /// 自动化名字。唯一。
  final String name;

  /// 触发器。
  final Trigger trigger;

  /// 要启动的流程名字。
  final String workflowName;

  /// 启动流程时的输入。
  final Map<String, Object?> inputs;

  /// 启动前约束。
  final List<Constraint> constraints;

  /// 流程完成后的后处理。
  final PostAction? onComplete;

  /// 冷却期。同一自动化在冷却期内只触发一次。
  final Duration cooldown;
}
