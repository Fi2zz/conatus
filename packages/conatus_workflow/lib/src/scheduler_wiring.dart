/// 触发器接线：把自动化挂到 cron / 遥测流上，注销时拆除。
library;

import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_alerting/conatus_alerting.dart';
import 'package:conatus_cron/conatus_cron.dart';

import 'automation.dart';

/// 触发器接线。持有 cron 任务与遥测订阅，触发时回调 [onTrigger]。
class SchedulerTriggerWiring {
  SchedulerTriggerWiring({
    required this.onTrigger,
    this.cron,
    this.telemetry,
  });

  /// 触发回调（已按 name 解析）。
  final void Function(String name) onTrigger;

  /// 定时服务；null 时定时触发不接线。
  final CronService? cron;

  /// 遥测服务；null 时事件/条件触发不接线。
  final Telemetry? telemetry;

  final Map<String, String> _cronIds = <String, String>{};
  final Map<String, StreamSubscription<TelemetryEvent>> _telemetrySubs =
      <String, StreamSubscription<TelemetryEvent>>{};

  /// 接线一个自动化。
  void wire(Automation automation) {
    switch (automation.trigger) {
      case CronTrigger(:final expression):
        _wireCron(automation.name, expression);
      case EventTrigger(:final eventName, :final filter):
        _wireEvent(automation.name, eventName, filter);
      case ConditionTrigger(:final rule):
        _wireCondition(automation.name, rule);
      case ManualTrigger():
        break;
    }
  }

  /// 拆除一个自动化的接线。
  void unwire(Automation automation) {
    final cronId = _cronIds.remove(automation.name);
    if (cronId != null) {
      try {
        cron?.removeDynamicTask(cronId);
      } on Object {
        // 任务可能已被外部删除；注销自动化不必失败。
      }
    }
    _telemetrySubs.remove(automation.name)?.cancel();
  }

  /// cron 交付入口：按任务 id 反查自动化并触发。未映射的任务直接受理。
  Future<bool> deliverCron(CronTask task) async {
    final name = _automationOf(task.id);
    if (name != null) onTrigger(name);
    return true;
  }

  /// 释放全部订阅。
  void dispose() {
    for (final sub in _telemetrySubs.values) {
      sub.cancel();
    }
    _telemetrySubs.clear();
  }

  void _wireCron(String name, String expression) {
    final view = cron?.addDynamicTask(<String, Object?>{
      'cron': expression,
      'prompt': name,
    });
    if (view != null) _cronIds[name] = view.id;
  }

  void _wireEvent(
      String name, String eventName, bool Function(TelemetryEvent)? filter) {
    final events = telemetry?.events;
    if (events == null) return;
    _telemetrySubs[name] = events.listen((TelemetryEvent event) {
      if (event.name == eventName && (filter?.call(event) ?? true)) {
        onTrigger(name);
      }
    });
  }

  void _wireCondition(String name, AlertRule rule) {
    final events = telemetry?.events;
    if (events == null) return;
    final ctx = AlertContext();
    ctx.registerCooldown(rule.name, rule.cooldown);
    _telemetrySubs[name] = events.listen((TelemetryEvent event) {
      if (ctx.isCoolingDown(rule.name)) return;
      if (!rule.condition(event, ctx)) return;
      ctx.markFired(rule.name);
      onTrigger(name);
    });
  }

  String? _automationOf(String taskId) {
    for (final entry in _cronIds.entries) {
      if (entry.value == taskId) return entry.key;
    }
    return null;
  }
}
