/// 流程调度器默认实现：注册、触发、冷却、约束、互斥与后处理。
library;

import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_cron/conatus_cron.dart';

import 'automation.dart';
import 'constraint.dart';
import 'engine.dart';
import 'post_action.dart';
import 'run.dart';
import 'scheduler.dart';
import 'scheduler_wiring.dart';

class WorkflowSchedulerImpl implements WorkflowScheduler {
  WorkflowSchedulerImpl({
    required this.workflow,
    this.cron,
    this.telemetry,
    Set<String> Function()? permissionsOf,
    DateTime Function()? now,
  })  : _permissionsOf = permissionsOf,
        _now = now ?? DateTime.now {
    _wiring = SchedulerTriggerWiring(
      cron: cron,
      telemetry: telemetry,
      onTrigger: _onWiredTrigger,
    );
    _runSub = workflow.changes.listen(_handleRunEvent);
  }

  final WorkflowEngine workflow;
  final CronService? cron;
  final Telemetry? telemetry;

  final Set<String> Function()? _permissionsOf;
  final DateTime Function() _now;
  final Map<String, Automation> _automations = <String, Automation>{};
  final Map<String, DateTime> _lastRun = <String, DateTime>{};
  final Map<String, String> _mutexRuns = <String, String>{};
  final Map<String, Automation> _runOwners = <String, Automation>{};
  final StreamController<SchedulerEvent> _changes =
      StreamController<SchedulerEvent>.broadcast();
  late final StreamSubscription<WorkflowEvent> _runSub;
  late final SchedulerTriggerWiring _wiring;
  bool _running = false;

  @override
  void register(Automation automation) {
    _automations[automation.name] = automation;
    _wiring.wire(automation);
    _changes.add(AutomationRegistered(automation));
    _emit('automation.registered', <String, Object?>{'name': automation.name});
  }

  @override
  void unregister(String name) {
    final automation = _automations.remove(name);
    if (automation == null) return;
    _wiring.unwire(automation);
    _lastRun.remove(name);
  }

  @override
  void start() => _running = true;

  @override
  void stop() => _running = false;

  @override
  Future<WorkflowRun?> trigger(String name) =>
      _runAutomation(name, manual: true);

  @override
  Future<bool> handleCronDelivery(
          String recordId, String framing, CronTask task) =>
      _wiring.deliverCron(task);

  @override
  List<Automation> get automations =>
      _automations.values.toList(growable: false);

  @override
  Stream<SchedulerEvent> get changes => _changes.stream;

  @override
  void dispose() {
    _runSub.cancel();
    _wiring.dispose();
    _changes.close();
  }

  void _onWiredTrigger(String name) {
    unawaited(_runAutomation(name, manual: false));
  }

  Future<WorkflowRun?> _runAutomation(String name,
      {required bool manual}) async {
    final automation = _automations[name];
    if (automation == null) return null;
    if (!_mayRun(manual, automation)) return null;
    _dropFinishedRuns();
    final blocked = await _checkConstraints(automation);
    if (blocked != null) return null;
    _lastRun[name] = _now();
    late final WorkflowRun run;
    try {
      run = await workflow.start(automation.workflowName,
          inputs: automation.inputs);
    } catch (error) {
      _emit('automation.failed', {'name': name, 'error': '$error'});
      rethrow;
    }
    _claimRun(automation, run);
    _changes.add(AutomationTriggered(name, run));
    _emit('automation.triggered', {'name': name, 'runId': run.id});
    return run;
  }

  bool _mayRun(bool manual, Automation automation) {
    if (!manual && !_running) return false;
    if (_coolingDown(automation.name, automation.cooldown)) return false;
    return true;
  }

  Future<String?> _checkConstraints(Automation automation) async {
    final ctx = ConstraintContext(
      now: _now,
      permissions: _permissionsOf?.call(),
      runningMutexes: _mutexRuns.keys.toSet(),
    );
    for (final constraint in automation.constraints) {
      final reason = await constraint.check(ctx);
      if (reason == null) continue;
      _changes.add(AutomationBlocked(automation.name, reason));
      _emit('automation.blocked', {'name': automation.name, 'reason': reason});
      return reason;
    }
    return null;
  }

  void _claimRun(Automation automation, WorkflowRun run) {
    _runOwners[run.id] = automation;
    for (final constraint in automation.constraints) {
      if (constraint is MutexConstraint) {
        _mutexRuns[constraint.mutexKey] = run.id;
      }
    }
  }

  bool _coolingDown(String name, Duration cooldown) {
    if (cooldown == Duration.zero) return false;
    final last = _lastRun[name];
    if (last == null) return false;
    return _now().difference(last) < cooldown;
  }

  void _dropFinishedRuns() {
    for (final entry in _mutexRuns.entries.toList()) {
      final run = workflow.run(entry.value);
      if (run == null || !run.status.isTerminal) continue;
      _mutexRuns.remove(entry.key);
      _runOwners.remove(entry.value);
    }
  }

  void _handleRunEvent(WorkflowEvent event) {
    final finished = _finishedRunOf(event);
    if (finished == null) return;
    final automation = _runOwners.remove(finished.id);
    if (automation == null) return;
    _releaseMutexesOf(finished.id);
    final onComplete = automation.onComplete;
    if (onComplete == null) return;
    unawaited(onComplete.execute(PostContext(
      automation: automation,
      result: finished,
      workflow: workflow,
    )));
  }

  WorkflowRun? _finishedRunOf(WorkflowEvent event) {
    if (event is RunCompleted) return event.run;
    if (event is RunFailed) return workflow.run(event.runId);
    return null;
  }

  void _releaseMutexesOf(String runId) {
    for (final entry in _mutexRuns.entries.toList()) {
      if (entry.value == runId) _mutexRuns.remove(entry.key);
    }
  }

  void _emit(String name, Map<String, Object?> data) {
    telemetry?.emit(TelemetryEvent(name, data: data));
  }
}
