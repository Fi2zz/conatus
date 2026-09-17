import 'package:conatus_workflow/conatus_workflow.dart';
import 'package:test/test.dart';

/// 节点 JSON 往返辅助。
Map<String, Object?> roundTrip(WorkflowNode node) =>
    Map<String, Object?>.from(node.toJson());

void main() {
  group('ToolNode', () {
    const ToolNode node = ToolNode(
      id: 'weather',
      dependsOn: <String>[],
      tool: 'weather_now',
      arguments: <String, Object?>{
        'city': '北京',
        'prev': '{{schedule.output.text}}',
      },
      when: '{{gps.output}} != null',
    );

    test('toJson / fromJson 往返一致', () {
      final ToolNode back = ToolNode.fromJson(roundTrip(node));
      expect(back.id, node.id);
      expect(back.dependsOn, node.dependsOn);
      expect(back.tool, node.tool);
      expect(back.arguments, node.arguments);
      expect(back.when, node.when);
    });

    test('fromJson 缺少 id 抛 WorkflowException', () {
      expect(
        () => ToolNode.fromJson(<String, Object?>{
          'type': 'tool',
          'dependsOn': <Object>[],
          'tool': 'weather_now',
        }),
        throwsA(
          isA<WorkflowException>().having(
            (WorkflowException e) => e.code,
            'code',
            'missing-field',
          ),
        ),
      );
    });
  });

  group('AgentNode', () {
    const AgentNode node = AgentNode(
      id: 'draft',
      dependsOn: <String>['weather'],
      task: '把天气写成一段播报稿',
      name: 'reporter',
      tools: <String>['read', 'search'],
      systemPrompt: 'You write briefings.',
    );

    test('toJson / fromJson 往返一致（含可空字段缺省）', () {
      final AgentNode back = AgentNode.fromJson(roundTrip(node));
      expect(back.id, node.id);
      expect(back.dependsOn, node.dependsOn);
      expect(back.task, node.task);
      expect(back.name, node.name);
      expect(back.tools, node.tools);
      expect(back.systemPrompt, node.systemPrompt);
      expect(back.when, isNull);
    });

    test('可空字段缺省时降级为 null', () {
      final AgentNode minimal = AgentNode.fromJson(<String, Object?>{
        'type': 'agent',
        'id': 'a',
        'dependsOn': <Object>[],
        'task': 'do',
      });
      expect(minimal.name, isNull);
      expect(minimal.tools, isNull);
      expect(minimal.systemPrompt, isNull);
    });
  });

  group('SubWorkflowNode', () {
    const SubWorkflowNode node = SubWorkflowNode(
      id: 'brief',
      dependsOn: <String>['draft'],
      workflow: 'read-aloud',
      inputs: <String, Object?>{'text': '{{draft.output}}'},
    );

    test('toJson / fromJson 往返一致', () {
      final SubWorkflowNode back = SubWorkflowNode.fromJson(roundTrip(node));
      expect(back.id, node.id);
      expect(back.dependsOn, node.dependsOn);
      expect(back.workflow, node.workflow);
      expect(back.inputs, node.inputs);
      expect(back.when, isNull);
    });
  });

  group('WorkflowNode.fromJson 分派', () {
    test('按 type 字段分派到对应子类', () {
      final WorkflowNode tool = WorkflowNode.fromJson(<String, Object?>{
        'type': 'tool',
        'id': 'a',
        'dependsOn': <Object>[],
        'tool': 't',
      });
      final WorkflowNode agent = WorkflowNode.fromJson(<String, Object?>{
        'type': 'agent',
        'id': 'b',
        'dependsOn': <Object>[],
        'task': 'do',
      });
      final WorkflowNode sub = WorkflowNode.fromJson(<String, Object?>{
        'type': 'subworkflow',
        'id': 'c',
        'dependsOn': <Object>[],
        'workflow': 'w',
      });
      expect(tool, isA<ToolNode>());
      expect(agent, isA<AgentNode>());
      expect(sub, isA<SubWorkflowNode>());
    });

    test('未知 type 抛 WorkflowException', () {
      expect(
        () => WorkflowNode.fromJson(<String, Object?>{
          'type': 'magic',
          'id': 'x',
          'dependsOn': <Object>[],
        }),
        throwsA(
          isA<WorkflowException>().having(
            (WorkflowException e) => e.code,
            'code',
            'unknown-node-type',
          ),
        ),
      );
    });
  });
}
