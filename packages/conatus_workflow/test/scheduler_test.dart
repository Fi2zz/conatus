import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_workflow/conatus_workflow.dart';
import 'package:test/test.dart';

void main() {
  test('register 后可见并发出注册事件', () async {
    final engine = _newEngine();
    final scheduler = _newScheduler(engine);
    final events = <SchedulerEvent>[];
    final sub = scheduler.changes.listen(events.add);

    const automation = Automation(
      name: 'daily',
      trigger: ManualTrigger(),
      workflowName: 'backup',
    );
    scheduler.register(automation);
    await _pump();

    expect(scheduler.automations.single.name, 'daily');
    expect(events.whereType<AutomationRegistered>().single.automation,
        same(automation));
    await sub.cancel();
    scheduler.dispose();
    engine.dispose();
  });

  test('unregister 移除自动化', () {
    final engine = _newEngine();
    final scheduler = _newScheduler(engine);
    const automation = Automation(
      name: 'daily',
      trigger: ManualTrigger(),
      workflowName: 'backup',
    );
    scheduler.register(automation);
    scheduler.unregister('daily');
    expect(scheduler.automations, isEmpty);
    scheduler.dispose();
    engine.dispose();
  });

  test('手动触发启动流程并发出触发事件', () async {
    final engine = _newEngine();
    await engine.register(_sampleDef('backup'));
    final scheduler = _newScheduler(engine);
    final events = <SchedulerEvent>[];
    final sub = scheduler.changes.listen(events.add);
    scheduler.register(const Automation(
      name: 'daily',
      trigger: ManualTrigger(),
      workflowName: 'backup',
    ));

    final run = await scheduler.trigger('daily');
    await _pump();

    expect(run, isNotNull);
    expect(run!.workflowName, 'backup');
    final triggered = events.whereType<AutomationTriggered>().single;
    expect(triggered.name, 'daily');
    expect(triggered.run?.id, run.id);
    await _drain(engine);
    await sub.cancel();
    scheduler.dispose();
    engine.dispose();
  });

  test('触发未注册的自动化返回 null', () async {
    final engine = _newEngine();
    final scheduler = _newScheduler(engine);
    expect(await scheduler.trigger('missing'), isNull);
    scheduler.dispose();
    engine.dispose();
  });

  test('冷却期内重复触发被忽略', () async {
    var current = DateTime(2026, 1, 1, 8);
    final engine = _newEngine();
    await engine.register(_sampleDef('backup'));
    final scheduler = _newScheduler(engine, now: () => current);
    scheduler.register(const Automation(
      name: 'daily',
      trigger: ManualTrigger(),
      workflowName: 'backup',
      cooldown: Duration(minutes: 10),
    ));

    final first = await scheduler.trigger('daily');
    expect(first, isNotNull);
    expect(await scheduler.trigger('daily'), isNull);

    current = current.add(const Duration(minutes: 11));
    expect(await scheduler.trigger('daily'), isNotNull);
    await _drain(engine);
    scheduler.dispose();
    engine.dispose();
  });

  test('约束不满足时阻塞并发出 blocked 事件与埋点', () async {
    final engine = _newEngine();
    await engine.register(_sampleDef('backup'));
    final telemetry = InMemoryTelemetry();
    final scheduler = _newScheduler(
      engine,
      telemetry: telemetry,
      permissionsOf: () => const <String>{},
    );
    final events = <SchedulerEvent>[];
    final sub = scheduler.changes.listen(events.add);
    scheduler.register(const Automation(
      name: 'guarded',
      trigger: ManualTrigger(),
      workflowName: 'backup',
      constraints: <Constraint>[
        PermissionConstraint(requiredPermissions: <String>{'admin'}),
      ],
    ));

    final run = await scheduler.trigger('guarded');
    await _pump();

    expect(run, isNull);
    final blocked = events.whereType<AutomationBlocked>().single;
    expect(blocked.name, 'guarded');
    expect(blocked.reason, contains('缺少权限'));
    expect(
      telemetry.recent.any((e) => e.name == 'automation.blocked'),
      isTrue,
    );
    await sub.cancel();
    scheduler.dispose();
    engine.dispose();
  });

  test('stop 后自动触发不生效，手动触发仍生效', () async {
    final engine = _newEngine();
    await engine.register(_sampleDef('backup'));
    final telemetry = InMemoryTelemetry();
    final scheduler = _newScheduler(engine, telemetry: telemetry);
    scheduler.register(const Automation(
      name: 'on-tool',
      trigger: EventTrigger('tool.called'),
      workflowName: 'backup',
    ));
    scheduler.register(const Automation(
      name: 'manual',
      trigger: ManualTrigger(),
      workflowName: 'backup',
    ));

    scheduler.start();
    telemetry.emit(TelemetryEvent('tool.called'));
    await _until(() => engine.runs.isNotEmpty);

    scheduler.stop();
    final runsBefore = engine.runs.length;
    telemetry.emit(TelemetryEvent('tool.called'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(engine.runs.length, runsBefore);
    expect(await scheduler.trigger('manual'), isNotNull);
    await _drain(engine);
    scheduler.dispose();
    engine.dispose();
  });
}

WorkflowEngine _newEngine() {
  return WorkflowEngineImpl(
    executor: (node, run) async => 'out:${node.id}',
  );
}

WorkflowDefinition _sampleDef(String name) => WorkflowDefinition(
      name: name,
      version: 1,
      nodes: [
        const ToolNode(
          id: 'step',
          dependsOn: [],
          tool: 'echo',
          arguments: {'text': 'hi'},
        ),
      ],
      outputs: ['step'],
    );

WorkflowScheduler _newScheduler(
  WorkflowEngine engine, {
  Telemetry? telemetry,
  DateTime Function()? now,
  Set<String> Function()? permissionsOf,
}) {
  return WorkflowSchedulerImpl(
    workflow: engine,
    telemetry: telemetry,
    now: now,
    permissionsOf: permissionsOf,
  );
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

Future<void> _drain(WorkflowEngine engine) =>
    _until(() => engine.runs.every((r) => r.status.isTerminal));

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('等待超时');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
