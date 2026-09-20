import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_workflow/conatus_workflow.dart';
import 'package:test/test.dart';

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

const kAutomation = Automation(
  name: 'nightly',
  trigger: ManualTrigger(),
  workflowName: 'backup',
);

final kRun = WorkflowRun(
  id: 'run-1',
  workflowName: 'backup',
  workflowVersion: 1,
  status: RunStatus.completed,
  inputs: const {},
  nodes: const {},
  createdAt: DateTime(2026),
);

void main() {
  group('NotifyAction', () {
    test('模板替换名称与状态', () async {
      final askUser = _FakeAskUser();
      final action =
          NotifyAction(askUser: askUser, template: '{name}:{status}');
      await action.execute(_ctx());
      expect(askUser.prompts, ['nightly:completed']);
    });

    test('缺省模板含名称', () async {
      final askUser = _FakeAskUser();
      final action = NotifyAction(askUser: askUser);
      await action.execute(_ctx());
      expect(askUser.prompts.single, contains('nightly'));
    });
  });

  group('RecordAction', () {
    test('追加 automation/completed 事件', () async {
      final session = Session(id: 's1');
      final action = RecordAction(session: session);
      await action.execute(_ctx());
      final event = session.events.single;
      expect(event.type, 'automation/completed');
      expect(event.data, isA<Map<String, Object?>>());
      expect(
          (event.data! as Map).keys, containsAll(['name', 'runId', 'status']));
    });
  });

  group('ChainAction', () {
    test('启动下一个流程并传输入', () async {
      final engine = _newEngine();
      await engine.register(_sampleDef('next'));
      const action = ChainAction(workflowName: 'next', inputs: {'x': 1});
      await action.execute(_ctx(workflow: engine));
      final run = engine.runs.single;
      expect(run.workflowName, 'next');
      expect(run.inputs, {'x': 1});
      await _until(() => engine.run(run.id)?.status.isTerminal ?? false);
      engine.dispose();
    });
  });

  group('CompositeAction', () {
    test('按序执行全部动作', () async {
      final askUser = _FakeAskUser();
      final action = CompositeAction(<PostAction>[
        NotifyAction(askUser: askUser, template: 'a'),
        NotifyAction(askUser: askUser, template: 'b'),
      ]);
      await action.execute(_ctx());
      expect(askUser.prompts, ['a', 'b']);
    });
  });
}

PostContext _ctx({WorkflowEngine? workflow}) => PostContext(
      automation: kAutomation,
      result: kRun,
      workflow: workflow ?? _sharedEngine(),
    );

WorkflowEngine? _shared;
WorkflowEngine _sharedEngine() => _shared ??= _newEngine();

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

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('等待超时');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
