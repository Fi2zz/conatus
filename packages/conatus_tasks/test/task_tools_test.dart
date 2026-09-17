import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_tasks/conatus_tasks.dart';
import 'package:test/test.dart';

Future<DefaultTaskCenter> _seededCenter() async {
  final DefaultTaskCenter center = DefaultTaskCenter();
  final Task running = await center.create(
    kind: TaskKind.agentTurn,
    description: '查机票',
  );
  await center.update(running.id, status: TaskStatus.running);
  await center.create(
    kind: TaskKind.subAgent,
    description: '盯快递',
    parentTaskId: running.id,
  );
  final Task shell = await center.create(
    kind: TaskKind.shell,
    description: 'npm test',
  );
  await center.update(shell.id, status: TaskStatus.completed);
  return center;
}

ToolContext _ctx(Map<String, Object?> arguments) =>
    ToolContext(ToolCall(name: kListTasksToolName, arguments: arguments));

void main() {
  group('ListTasksTool', () {
    test('无过滤列出全部任务', () async {
      final DefaultTaskCenter center = await _seededCenter();
      final ListTasksTool tool = ListTasksTool(taskCenter: center);

      final ToolResult result = await tool.call(_ctx(<String, Object?>{}));

      expect(result.isError, isFalse);
      expect(result.content, contains('现在共 3 个任务'));
      expect(result.content, contains('查机票'));
    });

    test('按状态过滤', () async {
      final DefaultTaskCenter center = await _seededCenter();
      final ListTasksTool tool = ListTasksTool(taskCenter: center);

      final ToolResult result =
          await tool.call(_ctx(<String, Object?>{'status': 'running'}));

      expect(result.content, contains('现在共 1 个任务'));
      expect(result.content, contains('查机票'));
    });

    test('按类型过滤', () async {
      final DefaultTaskCenter center = await _seededCenter();
      final ListTasksTool tool = ListTasksTool(taskCenter: center);

      final ToolResult result =
          await tool.call(_ctx(<String, Object?>{'kind': 'subAgent'}));

      expect(result.content, contains('盯快递'));
      expect(result.content, isNot(contains('查机票')));
    });

    test('按父任务过滤', () async {
      final DefaultTaskCenter center = await _seededCenter();
      final ListTasksTool tool = ListTasksTool(taskCenter: center);
      final String parentId =
          center.all.firstWhere((Task t) => t.description == '查机票').id;

      final ToolResult result =
          await tool.call(_ctx(<String, Object?>{'parent_id': parentId}));

      expect(result.content, contains('现在共 1 个任务'));
      expect(result.content, contains('盯快递'));
    });

    test('空结果口语化播报', () async {
      const ListTasksTool tool = ListTasksTool(taskCenter: _EmptyCenter());

      final ToolResult result = await tool.call(_ctx(<String, Object?>{}));

      expect(result.content, '现在没有任务。');
    });
  });

  group('CancelTaskTool', () {
    test('取消成功口语化确认', () async {
      final DefaultTaskCenter center = await _seededCenter();
      final CancelTaskTool tool = CancelTaskTool(taskCenter: center);
      final String id = center.all.first.id;

      final ToolResult result = await tool.call(ToolContext(ToolCall(
          name: kCancelTasksToolName, arguments: <String, Object?>{'id': id})));

      expect(result.isError, isFalse);
      expect(result.content, contains('已取消任务'));
      expect(center.get(id)!.status, TaskStatus.cancelled);
    });

    test('任务不存在返回失败结果', () async {
      final DefaultTaskCenter center = await _seededCenter();
      final CancelTaskTool tool = CancelTaskTool(taskCenter: center);

      final ToolResult result = await tool.call(const ToolContext(ToolCall(
          name: kCancelTasksToolName,
          arguments: <String, Object?>{'id': 'nope'})));

      expect(result.isError, isTrue);
      expect(result.error!.code, 'not-found');
    });

    test('审批拒绝时透传 cancelled', () async {
      final DefaultTaskCenter center =
          DefaultTaskCenter(approval: AutoApproval(false));
      final Task shell = await center.create(
        kind: TaskKind.shell,
        description: 'sleep 99',
      );
      final CancelTaskTool tool = CancelTaskTool(taskCenter: center);

      final ToolResult result = await tool.call(ToolContext(ToolCall(
          name: kCancelTasksToolName,
          arguments: <String, Object?>{'id': shell.id})));

      expect(result.isError, isTrue);
      expect(result.error!.code, 'cancelled');
    });
  });
}

class _EmptyCenter implements TaskCenter {
  const _EmptyCenter();

  @override
  Future<Task> create({
    required TaskKind kind,
    required String description,
    String? parentTaskId,
    Map<String, Object?>? metadata,
  }) =>
      throw UnimplementedError();

  @override
  Future<Task> update(String id,
          {TaskStatus? status, Object? result, Object? error}) =>
      throw UnimplementedError();

  @override
  Task? get(String id) => null;

  @override
  List<Task> get all => const <Task>[];

  @override
  List<Task> get active => const <Task>[];

  @override
  List<Task> childrenOf(String parentId) => const <Task>[];

  @override
  List<Task> subtreeOf(String id) => const <Task>[];

  @override
  Future<void> cancel(String id) => throw UnimplementedError();

  @override
  Future<void> cancelChildren(String id) => throw UnimplementedError();

  @override
  void registerCancel(String id, Future<void> Function() canceller) {}

  @override
  Stream<Task> get changes => const Stream<Task>.empty();

  @override
  void restore(Session session) {}

  @override
  void dispose() {}
}
