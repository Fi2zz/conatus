import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_alerting/conatus_alerting.dart';
import 'package:conatus_cron/conatus_cron.dart';
import 'package:conatus_workflow/conatus_workflow.dart';
import 'package:test/test.dart';

void main() {
  group('EventTrigger', () {
    test('事件名匹配时触发', () async {
      final engine = _newEngine();
      await engine.register(_sampleDef('backup'));
      final telemetry = InMemoryTelemetry();
      final scheduler = _newScheduler(engine, telemetry: telemetry);
      scheduler.start();
      scheduler.register(const Automation(
        name: 'on-tool',
        trigger: EventTrigger('tool.called'),
        workflowName: 'backup',
      ));

      telemetry.emit(TelemetryEvent('tool.called'));
      await _until(() => engine.runs.isNotEmpty);
      expect(engine.runs.single.workflowName, 'backup');
      await _drain(engine);
      scheduler.dispose();
      engine.dispose();
    });

    test('事件名不匹配不触发', () async {
      final engine = _newEngine();
      await engine.register(_sampleDef('backup'));
      final telemetry = InMemoryTelemetry();
      final scheduler = _newScheduler(engine, telemetry: telemetry);
      scheduler.start();
      scheduler.register(const Automation(
        name: 'on-tool',
        trigger: EventTrigger('tool.called'),
        workflowName: 'backup',
      ));

      telemetry.emit(TelemetryEvent('tool.failed'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(engine.runs, isEmpty);
      scheduler.dispose();
      engine.dispose();
    });

    test('过滤器不通过不触发', () async {
      final engine = _newEngine();
      await engine.register(_sampleDef('backup'));
      final telemetry = InMemoryTelemetry();
      final scheduler = _newScheduler(engine, telemetry: telemetry);
      scheduler.start();
      scheduler.register(const Automation(
        name: 'on-ok',
        trigger: EventTrigger('tool.called', filter: _wantsOk),
        workflowName: 'backup',
      ));

      telemetry.emit(TelemetryEvent('tool.called'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(engine.runs, isEmpty);

      telemetry.emit(TelemetryEvent('tool.called', data: {'ok': true}));
      await _until(() => engine.runs.isNotEmpty);
      await _drain(engine);
      scheduler.dispose();
      engine.dispose();
    });
  });

  group('ConditionTrigger', () {
    test('条件成立时触发', () async {
      final engine = _newEngine();
      await engine.register(_sampleDef('backup'));
      final telemetry = InMemoryTelemetry();
      final scheduler = _newScheduler(engine, telemetry: telemetry);
      scheduler.start();
      const rule = AlertRule(
        name: 'spike',
        severity: AlertSeverity.warning,
        condition: _spikeCondition,
        cooldown: Duration(minutes: 30),
      );
      scheduler.register(const Automation(
        name: 'cond',
        trigger: ConditionTrigger(rule),
        workflowName: 'backup',
      ));

      telemetry.emit(TelemetryEvent('metric.spike'));
      await _until(() => engine.runs.isNotEmpty);
      expect(engine.runs.single.workflowName, 'backup');
      await _drain(engine);
      scheduler.dispose();
      engine.dispose();
    });

    test('冷却期内不重复触发', () async {
      final engine = _newEngine();
      await engine.register(_sampleDef('backup'));
      final telemetry = InMemoryTelemetry();
      final scheduler = _newScheduler(engine, telemetry: telemetry);
      scheduler.start();
      const rule = AlertRule(
        name: 'spike',
        severity: AlertSeverity.warning,
        condition: _spikeCondition,
        cooldown: Duration(minutes: 30),
      );
      scheduler.register(const Automation(
        name: 'cond',
        trigger: ConditionTrigger(rule),
        workflowName: 'backup',
      ));

      telemetry.emit(TelemetryEvent('metric.spike'));
      await _until(() => engine.runs.length == 1);
      telemetry.emit(TelemetryEvent('metric.spike'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(engine.runs.length, 1);
      await _drain(engine);
      scheduler.dispose();
      engine.dispose();
    });
  });

  group('CronTrigger', () {
    test('注册为动态任务，交付映射回自动化', () async {
      final engine = _newEngine();
      await engine.register(_sampleDef('backup'));
      final cron = CronService(storage: _MemoryCronStorage());
      final scheduler = _newScheduler(engine, cron: cron);
      scheduler.start();
      scheduler.register(const Automation(
        name: 'daily',
        trigger: CronTrigger('0 9 * * *'),
        workflowName: 'backup',
      ));

      final task = cron.tasks.single;
      expect(task.prompt, 'daily');
      expect(task.cron, '0 9 * * *');

      final accepted =
          await scheduler.handleCronDelivery('rec-1', 'framing', task);
      expect(accepted, isTrue);
      await _until(() => engine.runs.isNotEmpty);
      expect(engine.runs.single.workflowName, 'backup');
      await _drain(engine);
      scheduler.dispose();
      engine.dispose();
    });

    test('未映射的任务直接受理不触发', () async {
      final engine = _newEngine();
      await engine.register(_sampleDef('backup'));
      final cron = CronService(storage: _MemoryCronStorage());
      final scheduler = _newScheduler(engine, cron: cron);
      scheduler.start();
      scheduler.register(const Automation(
        name: 'daily',
        trigger: CronTrigger('0 9 * * *'),
        workflowName: 'backup',
      ));
      final unknown = CronTask(
        id: 'task-unknown',
        prompt: 'x',
        origin: CronTaskOrigin.dynamic,
      );

      final accepted =
          await scheduler.handleCronDelivery('rec-2', 'framing', unknown);
      expect(accepted, isTrue);
      expect(engine.runs, isEmpty);
      scheduler.dispose();
      engine.dispose();
    });

    test('注销时移除动态任务', () async {
      final engine = _newEngine();
      final cron = CronService(storage: _MemoryCronStorage());
      final scheduler = _newScheduler(engine, cron: cron);
      scheduler.register(const Automation(
        name: 'daily',
        trigger: CronTrigger('0 9 * * *'),
        workflowName: 'backup',
      ));
      expect(cron.tasks, hasLength(1));

      scheduler.unregister('daily');
      expect(cron.tasks, isEmpty);
      scheduler.dispose();
      engine.dispose();
    });
  });
}

bool _wantsOk(TelemetryEvent event) => (event.data['ok'] as bool?) ?? false;

bool _spikeCondition(TelemetryEvent event, AlertContext ctx) =>
    event.name == 'metric.spike';

class _MemoryCronStorage implements CronStorage {
  CronStorageSnapshot _snapshot = const CronStorageSnapshot();
  final List<Map<String, Object?>> _history = <Map<String, Object?>>[];

  @override
  CronStorageSnapshot loadTasks() => _snapshot;

  @override
  void saveTasks({
    required List<Map<String, Object?>> tasks,
    required Map<String, CronRunStamp> runStamps,
    required Map<String, bool> overrides,
  }) {
    _snapshot = CronStorageSnapshot(
      dynamicTasks: tasks,
      runStamps: runStamps,
      overrides: overrides,
    );
  }

  @override
  List<Map<String, Object?>> loadHistory() => _history;

  @override
  void saveHistory(List<Map<String, Object?>> records) {
    _history
      ..clear()
      ..addAll(records);
  }
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
  CronService? cron,
}) {
  return WorkflowSchedulerImpl(
    workflow: engine,
    telemetry: telemetry,
    cron: cron,
  );
}

Future<void> _drain(WorkflowEngine engine) =>
    _until(() => engine.runs.every((r) => r.status.isTerminal));

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('等待超时');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
