import 'package:conatus_workflow/conatus_workflow.dart';
import 'package:test/test.dart';

/// 三种节点混合的完整流程定义样例。
WorkflowDefinition sampleDefinition() => const WorkflowDefinition(
      name: 'morning-brief',
      version: 1,
      description: '晨间播报',
      inputs: <WorkflowInput>[
        WorkflowInput(
          name: 'city',
          type: 'string',
          required: true,
          defaultValue: '北京',
          description: '城市',
        ),
        WorkflowInput(
          name: 'withSchedule',
          type: 'boolean',
          defaultValue: true,
        ),
      ],
      outputs: <String>['brief'],
      metadata: <String, Object?>{'author': 'demo'},
      nodes: <WorkflowNode>[
        ToolNode(id: 'weather', dependsOn: <String>[], tool: 'weather_now'),
        AgentNode(
          id: 'draft',
          dependsOn: <String>['weather'],
          task: '把天气写成播报稿',
        ),
        SubWorkflowNode(
          id: 'brief',
          dependsOn: <String>['draft'],
          workflow: 'read-aloud',
        ),
      ],
    );

void main() {
  group('WorkflowInput', () {
    test('toJson / fromJson 往返一致', () {
      const WorkflowInput input = WorkflowInput(
        name: 'city',
        type: 'string',
        required: true,
        defaultValue: '北京',
        description: '城市',
      );
      final WorkflowInput back =
          WorkflowInput.fromJson(Map<String, Object?>.from(input.toJson()));
      expect(back.name, input.name);
      expect(back.type, input.type);
      expect(back.required, isTrue);
      expect(back.defaultValue, input.defaultValue);
      expect(back.description, input.description);
    });

    test('defaultValue 为 null 时往返一致', () {
      final WorkflowInput back = WorkflowInput.fromJson(<String, Object?>{
        'name': 'x',
        'type': 'integer',
        'required': false,
      });
      expect(back.name, 'x');
      expect(back.type, 'integer');
      expect(back.required, isFalse);
      expect(back.defaultValue, isNull);
      expect(back.description, '');
    });
  });

  group('WorkflowDefinition', () {
    test('toJson / fromJson 往返一致（含三种节点混合）', () {
      final WorkflowDefinition back = WorkflowDefinition.fromJson(
        Map<String, Object?>.from(sampleDefinition().toJson()),
      );
      expect(back.name, 'morning-brief');
      expect(back.version, 1);
      expect(back.description, '晨间播报');
      expect(back.inputs.length, 2);
      expect(back.inputs.first.name, 'city');
      expect(back.outputs, const <String>['brief']);
      expect(back.metadata, const <String, Object?>{'author': 'demo'});
      expect(back.nodes, hasLength(3));
      expect(back.nodes[0], isA<ToolNode>());
      expect(back.nodes[1], isA<AgentNode>());
      expect(back.nodes[2], isA<SubWorkflowNode>());
      final ToolNode weather = back.nodes[0] as ToolNode;
      expect(weather.tool, 'weather_now');
    });

    test('可选字段缺省时降级为默认值', () {
      final WorkflowDefinition back = WorkflowDefinition.fromJson(
        <String, Object?>{
          'name': 'minimal',
          'version': 0,
          'nodes': <Object>[],
        },
      );
      expect(back.description, '');
      expect(back.inputs, isEmpty);
      expect(back.outputs, isEmpty);
      expect(back.metadata, isEmpty);
    });
  });

  group('WorkflowDefinition.fromJson 非法输入', () {
    final Map<String, Object?> base = <String, Object?>{
      'name': 'w',
      'version': 1,
      'nodes': <Object>[],
    };

    test('缺少 name 抛 WorkflowException', () {
      expect(
        () => WorkflowDefinition.fromJson(
          <String, Object?>{'version': 1, 'nodes': <Object>[]},
        ),
        throwsA(
          isA<WorkflowException>().having(
            (WorkflowException e) => e.code,
            'code',
            'missing-field',
          ),
        ),
      );
    });

    test('缺少 version 抛 WorkflowException', () {
      expect(
        () => WorkflowDefinition.fromJson(
          <String, Object?>{'name': 'w', 'nodes': <Object>[]},
        ),
        throwsA(isA<WorkflowException>()),
      );
    });

    test('缺少 nodes 抛 WorkflowException', () {
      expect(
        () => WorkflowDefinition.fromJson(
          <String, Object?>{'name': 'w', 'version': 1},
        ),
        throwsA(isA<WorkflowException>()),
      );
    });

    test('nodes 类型错误抛 WorkflowException', () {
      expect(
        () => WorkflowDefinition.fromJson(
          <String, Object?>{...base, 'nodes': 42},
        ),
        throwsA(
          isA<WorkflowException>().having(
            (WorkflowException e) => e.code,
            'code',
            'bad-type',
          ),
        ),
      );
    });

    test('节点缺少必填字段抛 WorkflowException', () {
      expect(
        () => WorkflowDefinition.fromJson(<String, Object?>{
          ...base,
          'nodes': <Object>[
            <String, Object?>{
              'type': 'tool',
              'id': 'a',
              'dependsOn': <Object>[]
            },
          ],
        }),
        throwsA(isA<WorkflowException>()),
      );
    });
  });
}
