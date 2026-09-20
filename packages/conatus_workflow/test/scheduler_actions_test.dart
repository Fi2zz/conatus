import 'dart:async';

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_workflow/conatus_workflow.dart';
import 'package:test/test.dart';

void main() {
  test('流程完成后执行 onComplete（NotifyAction）', () async {
    final engine = _newEngine();
    await engine.register(_sampleDef('backup'));
    final askUser = _FakeAskUser();
    final scheduler = _newScheduler(engine);
    scheduler.register(Automation(
      name: 'daily',
      trigger: const ManualTrigger(),
      workflowName: 'backup',
      onComplete: NotifyAction(askUser: askUser, template: '{name}:{status}'),
    ));

    final run = await scheduler.trigger('daily');
    await _waitTerminal(engine, run!.id);
    await _until(() => askUser.prompts.isNotEmpty);
    expect(askUser.prompts.single, 'daily:completed');
    scheduler.dispose();
    engine.dispose();
  });

  test('流程失败也执行 onComplete', () async {
    final engine = WorkflowEngineImpl(
      executor: (node, run) async => throw StateError('boom'),
    );
    await engine.register(_sampleDef('backup'));
    final askUser = _FakeAskUser();
    final scheduler = _newScheduler(engine);
    scheduler.register(Automation(
      name: 'daily',
      trigger: const ManualTrigger(),
      workflowName: 'backup',
      onComplete: NotifyAction(askUser: askUser, template: '{name}:{status}'),
    ));

    final run = await scheduler.trigger('daily');
    await _waitTerminal(engine, run!.id);
    await _until(() => askUser.prompts.isNotEmpty);
    expect(askUser.prompts.single, 'daily:failed');
    scheduler.dispose();
    engine.dispose();
  });

  test('RecordAction 记录到 Session', () async {
    final engine = _newEngine();
    await engine.register(_sampleDef('backup'));
    final session = Session(id: 's1');
    final scheduler = _newScheduler(engine);
    scheduler.register(Automation(
      name: 'daily',
      trigger: const ManualTrigger(),
      workflowName: 'backup',
      onComplete: RecordAction(session: session),
    ));

    final run = await scheduler.trigger('daily');
    await _waitTerminal(engine, run!.id);
    await _until(() => session.events.isNotEmpty);
    expect(session.events.single.type, 'automation/completed');
    scheduler.dispose();
    engine.dispose();
  });

  test('ChainAction 完成后触发下一个流程', () async {
    final engine = _newEngine();
    await engine.register(_sampleDef('backup'));
    await engine.register(_sampleDef('next'));
    final scheduler = _newScheduler(engine);
    scheduler.register(Automation(
      name: 'daily',
      trigger: const ManualTrigger(),
      workflowName: 'backup',
      onComplete: const ChainAction(workflowName: 'next'),
    ));

    final run = await scheduler.trigger('daily');
    await _waitTerminal(engine, run!.id);
    await _until(() => engine.runs.length == 2);
    expect(engine.runs.last.workflowName, 'next');
    await _drain(engine);
    scheduler.dispose();
    engine.dispose();
  });

  test('CompositeAction 按序执行', () async {
    final engine = _newEngine();
    await engine.register(_sampleDef('backup'));
    final askUser = _FakeAskUser();
    final scheduler = _newScheduler(engine);
    scheduler.register(Automation(
      name: 'daily',
      trigger: const ManualTrigger(),
      workflowName: 'backup',
      onComplete: CompositeAction(<PostAction>[
        NotifyAction(askUser: askUser, template: 'a'),
        NotifyAction(askUser: askUser, template: 'b'),
      ]),
    ));

    final run = await scheduler.trigger('daily');
    await _waitTerminal(engine, run!.id);
    await _until(() => askUser.prompts.length == 2);
    expect(askUser.prompts, ['a', 'b']);
    scheduler.dispose();
    engine.dispose();
  });

  test('互斥：运行中阻塞第二个，完成后释放', () async {
    final gate = Completer<void>();
    final engine = WorkflowEngineImpl(
      executor: (node, run) async {
        await gate.future;
        return 'done';
      },
    );
    await engine.register(_sampleDef('slow'));
    await engine.register(_sampleDef('fast'));
    final scheduler = _newScheduler(engine);
    scheduler.register(const Automation(
      name: 'a',
      trigger: const ManualTrigger(),
      workflowName: 'slow',
      constraints: <Constraint>[MutexConstraint('m')],
    ));
    scheduler.register(const Automation(
      name: 'b',
      trigger: const ManualTrigger(),
      workflowName: 'fast',
      constraints: <Constraint>[MutexConstraint('m')],
    ));

    final runA = await scheduler.trigger('a');
    expect(await scheduler.trigger('b'), isNull);

    gate.complete();
    await _waitTerminal(engine, runA!.id);
    final runB = await scheduler.trigger('b');
    expect(runB, isNotNull);
    await _drain(engine);
    scheduler.dispose();
    engine.dispose();
  });
}

class _FakeAskUser implements AskUser {
  final List<String> prompts = <String>[];

  @override
  Future<String> ask(String prompt) async {
    prompts.add(prompt);
    return 'ok';
  }

  @override
  void cancel() {}
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

WorkflowScheduler _newScheduler(WorkflowEngine engine) {
  return WorkflowSchedulerImpl(workflow: engine);
}

Future<void> _waitTerminal(WorkflowEngine engine, String runId) async {
  await _until(() => engine.run(runId)?.status.isTerminal ?? false);
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
