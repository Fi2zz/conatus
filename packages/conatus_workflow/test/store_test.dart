import 'package:conatus_workflow/conatus_workflow.dart';
import 'package:test/test.dart';

WorkflowDefinition sampleDef(String name, int version) => WorkflowDefinition(
      name: name,
      version: version,
      nodes: const <WorkflowNode>[],
    );

WorkflowRun sampleRun(String id) => WorkflowRun(
      id: id,
      workflowName: 'w',
      workflowVersion: 1,
      status: RunStatus.completed,
      inputs: const <String, Object?>{},
      nodes: const <String, RunNode>{},
      createdAt: DateTime.utc(2026, 9, 17),
    );

void main() {
  group('InMemoryWorkflowStore 流程定义', () {
    late InMemoryWorkflowStore store;

    setUp(() {
      store = InMemoryWorkflowStore();
    });

    test('保存/加载，同名覆盖', () async {
      await store.saveDefinition(sampleDef('w', 1));
      final WorkflowDefinition? loaded = await store.loadDefinition('w');
      expect(loaded?.name, 'w');
      expect(loaded?.version, 1);

      await store.saveDefinition(sampleDef('w', 2));
      expect((await store.loadDefinition('w'))?.version, 2);
    });

    test('加载不存在的定义返回 null', () async {
      expect(await store.loadDefinition('missing'), isNull);
    });

    test('列出与删除，删除不存在幂等', () async {
      await store.saveDefinition(sampleDef('a', 1));
      await store.saveDefinition(sampleDef('b', 1));
      expect(
        (await store.listDefinitions()).map((WorkflowDefinition d) => d.name),
        <String>['a', 'b'],
      );

      await store.deleteDefinition('a');
      expect(
        (await store.listDefinitions()).map((WorkflowDefinition d) => d.name),
        <String>['b'],
      );
      await store.deleteDefinition('nope');
    });
  });

  group('InMemoryWorkflowStore 运行', () {
    late InMemoryWorkflowStore store;

    setUp(() {
      store = InMemoryWorkflowStore();
    });

    test('保存/加载，同名覆盖', () async {
      await store.saveRun(sampleRun('r1'));
      final WorkflowRun? loaded = await store.loadRun('r1');
      expect(loaded?.id, 'r1');
      expect(loaded?.status, RunStatus.completed);

      await store.saveRun(
        sampleRun('r1').copyWith(status: RunStatus.failed),
      );
      expect((await store.loadRun('r1'))?.status, RunStatus.failed);
    });

    test('加载不存在的运行返回 null', () async {
      expect(await store.loadRun('missing'), isNull);
    });

    test('列出与删除，删除不存在幂等', () async {
      await store.saveRun(sampleRun('r1'));
      await store.saveRun(sampleRun('r2'));
      expect(
        (await store.listRuns()).map((WorkflowRun r) => r.id),
        <String>['r1', 'r2'],
      );

      await store.deleteRun('r1');
      expect(
        (await store.listRuns()).map((WorkflowRun r) => r.id),
        <String>['r2'],
      );
      await store.deleteRun('nope');
    });

    test('定义与运行互不干扰', () async {
      await store.saveDefinition(sampleDef('w', 1));
      await store.saveRun(sampleRun('w'));
      expect((await store.loadDefinition('w'))?.version, 1);
      expect((await store.loadRun('w'))?.id, 'w');
      expect((await store.listDefinitions()), hasLength(1));
      expect((await store.listRuns()), hasLength(1));
    });
  });
}
