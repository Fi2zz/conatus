/// 告警服务：订阅遥测事件流，检测规则并通知。
library;

import 'dart:async';
import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';

import 'alert.dart';
import 'notifiers/console_notifier.dart';
import 'notifiers/notifier.dart';
import 'rule.dart';
import 'rules/default_rules.dart';

/// 告警服务。
abstract class Alerting {
  /// 当前注册的规则（按名字）。
  List<AlertRule> get rules;

  /// 当前活跃的告警（未解决）。
  List<Alert> get activeAlerts;

  /// 历史告警。
  List<Alert> get history;

  /// 告警流。
  Stream<Alert> get alerts;

  /// 添加规则（同名覆盖并重注册冷却期）。
  void addRule(AlertRule rule);

  /// 移除规则。
  void removeRule(String name);

  /// 手动触发一次告警（用于测试与外部调用，不经过冷却）。
  Future<void> fire(Alert alert);

  /// 解决一个告警。
  void resolve(String alertId);

  /// 释放资源。幂等。
  void dispose();
}

/// [Alerting] 的默认实现：订阅 [Telemetry.events]，逐规则判定。
///
/// - 单条规则条件抛异常不影响其他规则（记录到 stderr）；
/// - 通知失败不阻塞主流程（`unawaited` + 内部 try-catch）；
/// - 每分钟 [AlertContext.prune]，防止窗口统计内存增长。
class AlertingImpl implements Alerting {
  /// 构造。[now] 注入时钟（测试用）。
  AlertingImpl({
    required this.telemetry,
    required this.notifier,
    List<AlertRule>? rules,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _ctx = AlertContext(now: _now);
    for (final AlertRule rule in rules ?? defaultAlertRules()) {
      _rules[rule.name] = rule;
      _ctx.registerCooldown(rule.name, rule.cooldown);
    }
    _subscription = telemetry.events.listen(_check);
    _pruneTimer = Timer.periodic(const Duration(minutes: 1), (_) => _ctx.prune());
  }

  /// 事件流来源。
  final Telemetry telemetry;

  /// 通知渠道。
  final AlertNotifier notifier;

  final DateTime Function() _now;
  final Map<String, AlertRule> _rules = <String, AlertRule>{};
  late final AlertContext _ctx;
  final List<Alert> _active = <Alert>[];
  final List<Alert> _history = <Alert>[];
  final StreamController<Alert> _alerts = StreamController<Alert>.broadcast();
  StreamSubscription<TelemetryEvent>? _subscription;
  Timer? _pruneTimer;
  bool _disposed = false;

  @override
  List<AlertRule> get rules => List<AlertRule>.unmodifiable(_rules.values);

  @override
  List<Alert> get activeAlerts => List<Alert>.unmodifiable(_active);

  @override
  List<Alert> get history => List<Alert>.unmodifiable(_history);

  @override
  Stream<Alert> get alerts => _alerts.stream;

  @override
  void addRule(AlertRule rule) {
    _rules[rule.name] = rule;
    _ctx.registerCooldown(rule.name, rule.cooldown);
  }

  @override
  void removeRule(String name) {
    _rules.remove(name);
  }

  @override
  Future<void> fire(Alert alert) async {
    _active.add(alert);
    _history.add(alert);
    if (!_alerts.isClosed) _alerts.add(alert);
    await _notify(alert);
  }

  @override
  void resolve(String alertId) {
    _active.removeWhere((Alert alert) => alert.id == alertId);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _subscription?.cancel();
    _pruneTimer?.cancel();
    _alerts.close();
    notifier.dispose();
  }

  void _check(TelemetryEvent event) {
    for (final AlertRule rule in _rules.values) {
      if (_ctx.isCoolingDown(rule.name)) continue;
      try {
        if (rule.condition(event, _ctx)) {
          _ctx.markFired(rule.name);
          final Alert alert = Alert(
            id: 'alert-${_now().microsecondsSinceEpoch}',
            rule: rule.name,
            severity: rule.severity,
            event: event,
            firedAt: _now(),
            sessionId: event.data['sessionId'] as String?,
            goalId: event.data['goalId'] as String?,
          );
          _active.add(alert);
          _history.add(alert);
          if (!_alerts.isClosed) _alerts.add(alert);
          unawaited(_notify(alert));
        }
      } catch (error) {
        stderr.writeln('[alerting] 规则 ${rule.name} 执行失败: $error');
      }
    }
  }

  Future<void> _notify(Alert alert) async {
    try {
      await notifier.notify(alert);
    } catch (error) {
      stderr.writeln('[alerting] 通知失败: $error');
    }
  }
}

/// `ctx.alerting`：当前上下文可见的告警服务。
extension AlertingContext on Context {
  /// 取当前上下文可见的 [Alerting]（未提供时抛 [StateError]）。
  Alerting get alerting => require<Alerting>('alerting');
}

/// 提供 `'alerting'` 服务。
///
/// 依赖（全部可选，缺省时降级）：
/// - [telemetry]：订阅事件流（必需，缺省 `ctx.telemetry`）；
/// - [notifier]：通知渠道（缺省 [ConsoleNotifier]）；
/// - [rules]：规则集（缺省 [defaultAlertRules]）。
///
/// 服务随 [ctx] 释放自动 [Alerting.dispose]。同一上下文重复提供抛
/// [StateError]。
Alerting provideAlerting(
  Context ctx, {
  Alerting? alerting,
  List<AlertRule>? rules,
  AlertNotifier? notifier,
  Telemetry? telemetry,
}) {
  final Alerting resolved = alerting ??
      AlertingImpl(
        telemetry: telemetry ?? ctx.require<Telemetry>('telemetry'),
        notifier: notifier ?? ConsoleNotifier(),
        rules: rules ?? defaultAlertRules(),
      );
  ctx.provide('alerting', resolved);
  ctx.onDispose(resolved.dispose);
  return resolved;
}
