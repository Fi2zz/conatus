import 'package:conatus_workflow/conatus_workflow.dart';
import 'package:test/test.dart';

WorkflowRun runWith({
  Map<String, Object?> inputs = const <String, Object?>{},
  Map<String, RunNode> nodes = const <String, RunNode>{},
}) =>
    WorkflowRun(
      id: 'r',
      workflowName: 'w',
      workflowVersion: 1,
      status: RunStatus.running,
      inputs: inputs,
      nodes: nodes,
      createdAt: DateTime.utc(2026, 9, 17),
    );

RunNode doneNode(Object? outputs) => RunNode(
      id: 'a',
      status: RunNodeStatus.completed,
      inputs: const <String, Object?>{},
      outputs: outputs,
    );

void main() {
  group('resolveReference', () {
    final run = runWith(
      inputs: <String, Object?>{'city': '北京'},
      nodes: <String, RunNode>{
        'weather': doneNode(<String, Object?>{'temp': 22, 'desc': '晴'}),
        'raw': doneNode('标量'),
      },
    );

    test('取节点输出的 map 字段', () {
      expect(resolveReference('weather.temp', run), 22);
      expect(resolveReference('weather.desc', run), '晴');
    });

    test('取节点整个输出与标量输出', () {
      expect(resolveReference('raw', run), '标量');
      expect(
        resolveReference('weather', run),
        const <String, Object?>{'temp': 22, 'desc': '晴'},
      );
    });

    test('取运行输入', () {
      expect(resolveReference('inputs.city', run), '北京');
      expect(resolveReference('inputs', run),
          const <String, Object?>{'city': '北京'});
    });

    test('引用不存在的节点抛 WorkflowException', () {
      expect(
        () => resolveReference('ghost', run),
        throwsA(
          isA<WorkflowException>().having(
            (WorkflowException e) => e.code,
            'code',
            'unknown-node',
          ),
        ),
      );
    });

    test('引用未完成节点抛 WorkflowException', () {
      final pending = runWith(
        nodes: <String, RunNode>{
          'x': const RunNode(
            id: 'x',
            status: RunNodeStatus.pending,
            inputs: <String, Object?>{},
          ),
        },
      );
      expect(
        () => resolveReference('x.output', pending),
        throwsA(
          isA<WorkflowException>().having(
            (WorkflowException e) => e.code,
            'code',
            'node-not-completed',
          ),
        ),
      );
    });

    test('标量输出上取字段抛 WorkflowException', () {
      final scalar = runWith(
        nodes: <String, RunNode>{'raw': doneNode('标量')},
      );
      expect(
        () => resolveReference('raw.field', scalar),
        throwsA(
          isA<WorkflowException>().having(
            (WorkflowException e) => e.code,
            'code',
            'bad-reference',
          ),
        ),
      );
    });
  });

  group('resolveArguments', () {
    test('整体引用替换为原值，字面量原样保留', () {
      final run = runWith(
        inputs: <String, Object?>{'city': '北京'},
        nodes: <String, RunNode>{
          'weather': doneNode(<String, Object?>{'temp': 22}),
        },
      );
      expect(
        resolveArguments(<String, Object?>{
          'city': '{{inputs.city}}',
          'prev': '{{weather.temp}}',
          'plain': '你好',
          'nested': <String, Object?>{
            'inner': '{{weather.temp}}',
            'list': <Object?>['{{inputs.city}}', 1],
          },
        }, run),
        <String, Object?>{
          'city': '北京',
          'prev': 22,
          'plain': '你好',
          'nested': <String, Object?>{
            'inner': 22,
            'list': <Object?>['北京', 1],
          },
        },
      );
    });

    test('非引用字符串与 null 原样保留', () {
      final run = runWith();
      expect(
        resolveArguments(<String, Object?>{'a': 'plain', 'b': null}, run),
        <String, Object?>{'a': 'plain', 'b': null},
      );
    });
  });

  group('evaluateCondition', () {
    final run = runWith(
      inputs: <String, Object?>{'city': '北京'},
      nodes: <String, RunNode>{
        'weather': doneNode(<String, Object?>{'temp': 22, 'desc': '晴'}),
        'raw': doneNode('标量'),
      },
    );

    test('相等 / 不等 / 非空', () {
      expect(evaluateCondition('{{inputs.city}} == "北京"', run), isTrue);
      expect(evaluateCondition('{{inputs.city}} != "上海"', run), isTrue);
      expect(evaluateCondition('{{inputs.city}} != null', run), isTrue);
      expect(evaluateCondition('{{weather.temp}} == 22', run), isTrue);
      expect(evaluateCondition('{{weather.temp}} == 23', run), isFalse);
    });

    test('逻辑与 / 逻辑或', () {
      expect(
        evaluateCondition(
            '{{weather.temp}} == 22 && {{weather.desc}} == "晴"', run),
        isTrue,
      );
      expect(
        evaluateCondition(
            '{{weather.temp}} == 22 && {{weather.desc}} == "雨"', run),
        isFalse,
      );
      expect(
        evaluateCondition(
            '{{weather.temp}} == 99 || {{weather.desc}} == "晴"', run),
        isTrue,
      );
    });

    test('布尔与数值字面量', () {
      final boolRun = runWith(
        nodes: <String, RunNode>{'f': doneNode(true)},
      );
      expect(evaluateCondition('{{f}} == true', boolRun), isTrue);
      expect(evaluateCondition('{{weather.temp}} == 22.0', run), isTrue);
    });

    test('非法表达式抛 WorkflowException', () {
      expect(
        () => evaluateCondition('{{weather.temp}} + 1', run),
        throwsA(
          isA<WorkflowException>().having(
            (WorkflowException e) => e.code,
            'code',
            'bad-condition',
          ),
        ),
      );
    });
  });

  group('引擎 when 条件', () {
    test('条件不满足的节点跳过，后续继续执行', () async {
      final engine = WorkflowEngineImpl(
        executor: (WorkflowNode node, WorkflowRun run) async => 'out',
      );
      await engine.register(
        const WorkflowDefinition(
          name: 'cond',
          version: 1,
          outputs: <String>['b'],
          nodes: <WorkflowNode>[
            ToolNode(
              id: 'a',
              dependsOn: <String>[],
              tool: 'noop',
              when: '{{inputs.skip}} != true',
            ),
            ToolNode(id: 'b', dependsOn: <String>['a'], tool: 'noop'),
          ],
        ),
      );

      final run = await engine.start(
        'cond',
        inputs: <String, Object?>{'skip': true},
      );
      await _waitFor(run.id, engine, RunStatus.completed);

      final result = engine.run(run.id)!;
      expect(result.nodes['a']?.status, RunNodeStatus.skipped);
      expect(result.nodes['b']?.status, RunNodeStatus.completed);
      expect(result.outputs, const <String, Object?>{'b': 'out'});
      engine.dispose();
    });

    test('条件满足的节点正常执行', () async {
      final engine = WorkflowEngineImpl(
        executor: (WorkflowNode node, WorkflowRun run) async => 'out',
      );
      await engine.register(
        const WorkflowDefinition(
          name: 'cond2',
          version: 1,
          nodes: <WorkflowNode>[
            ToolNode(
              id: 'a',
              dependsOn: <String>[],
              tool: 'noop',
              when: '{{inputs.skip}} != true',
            ),
          ],
        ),
      );

      final run = await engine.start(
        'cond2',
        inputs: <String, Object?>{'skip': false},
      );
      await _waitFor(run.id, engine, RunStatus.completed);

      expect(engine.run(run.id)?.nodes['a']?.status, RunNodeStatus.completed);
      engine.dispose();
    });
  });
}

Future<void> _waitFor(
  String runId,
  WorkflowEngine engine,
  RunStatus status,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (engine.run(runId)?.status != status) {
    if (DateTime.now().isAfter(deadline)) fail('等待运行状态超时');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
